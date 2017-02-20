Require Import CCL.
Require Import OptimisticTranslator OptimisticFS.

Require AsyncFS.
(* imports for DirTreeRep.rep *)
Import Log FSLayout Inode.INODE BFile.

(* various other imports *)
Import BFILE.
Import SuperBlock.
Import GenSepN.
Import Pred.

Require Import HomeDirProtocol.

Record FsParams :=
  { fsmem: ident;
    fstree: ident;
    fshomedirs: ident; }.

Section ConcurrentFS.

  Variable fsxp: fs_xparams.
  Variable CP:CacheParams.
  Variable P:FsParams.

  Definition fs_rep vd hm mscs tree :=
    exists ds ilist frees,
      LOG.rep (FSLayout.FSXPLog fsxp) (SB.rep fsxp)
              (LOG.NoTxn ds) (MSLL mscs) hm (add_buffers vd) /\
      (DirTreeRep.rep fsxp Pred.emp tree ilist frees)
        (list2nmem (ds!!)).

  Definition fs_invariant d hm tree (homedirs: TID -> list string) : heappred :=
    (fstree P |-> abs tree *
     fshomedirs P |-> abs homedirs *
     exists mscs vd, CacheRep CP d empty_writebuffer vd vd *
                fsmem P |-> val mscs *
                [[ fs_rep vd hm mscs tree ]])%pred.

  Definition fs_guarantee tid (sigma sigma': Sigma) :=
    exists tree tree' homedirs,
      fs_invariant (Sigma.disk sigma) (Sigma.hm sigma) tree homedirs (Sigma.mem sigma) /\
      fs_invariant (Sigma.disk sigma') (Sigma.hm sigma') tree' homedirs (Sigma.mem sigma') /\
      homedir_guarantee tid homedirs tree tree'.

  Lemma fs_rely_sametree : forall tid sigma sigma' tree homedirs,
      fs_invariant (Sigma.disk sigma) (Sigma.hm sigma) tree homedirs (Sigma.mem sigma) ->
      fs_invariant (Sigma.disk sigma') (Sigma.hm sigma') tree homedirs (Sigma.mem sigma') ->
      Rely fs_guarantee tid sigma sigma'.
  Proof.
    intros.
    constructor.
    exists (S tid); intuition.
    unfold fs_guarantee.
    descend; intuition eauto.
    reflexivity.
  Qed.

  Section InvariantUniqueness.

    Ltac mem_eq m a v :=
      match goal with
      | [ H: context[ptsto a v] |- _ ] =>
        let Hptsto := fresh in
        assert ((exists F, F * a |-> v)%pred m) as Hptsto by
              (SepAuto.pred_apply' H; SepAuto.cancel);
        unfold exis in Hptsto; destruct Hptsto;
        apply ptsto_valid' in Hptsto
      end.

    Lemma fs_invariant_tree_unique : forall d hm tree homedirs
                                       d' hm' tree' homedirs' m,
        fs_invariant d hm tree homedirs m ->
        fs_invariant d' hm' tree' homedirs' m ->
        tree = tree'.
    Proof.
      unfold fs_invariant; intros.
      mem_eq m (fstree P) (abs tree).
      mem_eq m (fstree P) (abs tree').
      rewrite H1 in H2; inversion H2; inj_pair2.
      auto.
    Qed.

    Lemma fs_invariant_homedirs_unique : forall d hm tree homedirs
                                       d' hm' tree' homedirs' m,
        fs_invariant d hm tree homedirs m ->
        fs_invariant d' hm' tree' homedirs' m ->
        homedirs = homedirs'.
    Proof.
      unfold fs_invariant; intros.
      mem_eq m (fshomedirs P) (abs homedirs).
      mem_eq m (fshomedirs P) (abs homedirs').
      rewrite H1 in H2; inversion H2; inj_pair2.
      auto.
    Qed.

  End InvariantUniqueness.

  Ltac invariant_unique :=
    repeat match goal with
           | [ H: fs_invariant _ _ ?tree _ ?m,
                  H': fs_invariant _ _ ?tree' _ ?m |- _ ] =>
             first [ constr_eq tree tree'; fail 1 | assert (tree' = tree) by
                         apply (fs_invariant_tree_unique H' H); subst ]
           | [ H: fs_invariant _ _ _ ?homedirs ?m,
                  H': fs_invariant _ _ _ ?homedirs' ?m |- _ ] =>
             first [ constr_eq homedirs homedirs'; fail 1 | assert (homedirs' = homedirs) by
                         apply (fs_invariant_homedirs_unique H' H); subst ]
           end.

  Theorem fs_rely_invariant : forall tid sigma sigma' tree homedirs,
      fs_invariant (Sigma.disk sigma) (Sigma.hm sigma) tree homedirs (Sigma.mem sigma) ->
      Rely fs_guarantee tid sigma sigma' ->
      exists tree', fs_invariant (Sigma.disk sigma') (Sigma.hm sigma') tree' homedirs (Sigma.mem sigma').
  Proof.
    unfold fs_guarantee; intros.
    generalize dependent tree.
    induction H0; intros; repeat deex; eauto.
    invariant_unique.
    eauto.
    edestruct IHclos_refl_trans1; eauto.
  Qed.

  Lemma fs_rely_invariant' : forall tid sigma sigma',
      Rely fs_guarantee tid sigma sigma' ->
      forall tree homedirs,
        fs_invariant (Sigma.disk sigma) (Sigma.hm sigma) tree homedirs (Sigma.mem sigma) ->
        exists tree',
          fs_invariant (Sigma.disk sigma') (Sigma.hm sigma') tree' homedirs (Sigma.mem sigma').
  Proof.
    intros.
    eapply fs_rely_invariant; eauto.
  Qed.

  Theorem fs_homedir_rely : forall tid sigma sigma' tree homedirs tree',
      fs_invariant (Sigma.disk sigma) (Sigma.hm sigma) tree homedirs (Sigma.mem sigma) ->
      Rely fs_guarantee tid sigma sigma' ->
      fs_invariant (Sigma.disk sigma') (Sigma.hm sigma') tree' homedirs (Sigma.mem sigma') ->
      homedir_rely tid homedirs tree tree'.
  Proof.
    unfold fs_guarantee; intros.
    generalize dependent tree'.
    generalize dependent tree.
    apply Operators_Properties.clos_rt_rt1n in H0.
    induction H0; intros; repeat deex; invariant_unique.
    - reflexivity.
    - match goal with
      | [ H: homedir_guarantee _ _ _ _ |- _ ] =>
        specialize (H _ ltac:(eauto))
      end.
      specialize (IHclos_refl_trans_1n _ ltac:(eauto) _ ltac:(eauto)).
      unfold homedir_rely in *; congruence.
  Qed.

  Lemma fs_rely_preserves_subtree : forall tid sigma sigma' tree homedirs tree' path f,
      find_subtree (homedirs tid ++ path) tree = Some f ->
      fs_invariant (Sigma.disk sigma) (Sigma.hm sigma) tree homedirs (Sigma.mem sigma) ->
      Rely fs_guarantee tid sigma sigma' ->
      fs_invariant (Sigma.disk sigma') (Sigma.hm sigma') tree' homedirs (Sigma.mem sigma') ->
      find_subtree (homedirs tid ++ path) tree' = Some f.
  Proof.
    intros.
    eapply fs_homedir_rely in H1; eauto.
    unfold homedir_rely in H1.
    eapply find_subtree_app' in H; repeat deex.
    erewrite find_subtree_app; eauto.
    congruence.
  Qed.

  Theorem fs_guarantee_refl : forall tid sigma homedirs,
      (exists tree, fs_invariant (Sigma.disk sigma) (Sigma.hm sigma) tree homedirs (Sigma.mem sigma)) ->
      fs_guarantee tid sigma sigma.
  Proof.
    intros; deex.
    unfold fs_guarantee; descend; intuition eauto.
    reflexivity.
  Qed.

  Theorem fs_guarantee_trans : forall tid sigma sigma' sigma'',
      fs_guarantee tid sigma sigma' ->
      fs_guarantee tid sigma' sigma'' ->
      fs_guarantee tid sigma sigma''.
  Proof.
    unfold fs_guarantee; intuition.
    repeat deex; invariant_unique.

    descend; intuition eauto.
    etransitivity; eauto.
  Qed.

  (* TODO: eventually abstract away protocol *)

  Definition guard {T} (r: Result T) : {exists v, r=Success v} + {r=Failed}.
    destruct r; eauto.
  Defined.

  Definition retry_syscall T
             (p: memstate -> cprog (Result (memstate * T) * WriteBuffer))
             (update: dirtree -> dirtree)
    : cprog (Result T) :=
    retry guard (ms <- Get _ (fsmem P);
                   do '(r, wb) <- p ms;
                   match r with
                   | Success (ms', r) =>
                     _ <- CacheCommit CP wb;
                       _ <- Assgn (fsmem P) ms';
                       _ <- GhostUpdate (fstree P) (fun _ => update);
                       Ret (Success r)
                   | Failed =>
                     _ <- CacheAbort;
                       _ <- Yield;
                       Ret Failed
                   end).

  Definition file_get_attr inum :=
    retry_syscall (fun mscs =>
                     OptFS.file_get_attr CP fsxp inum mscs empty_writebuffer)
                  (fun tree => tree).

  Ltac break_tuple :=
    match goal with
    | [ H: context[let (n, m) := ?a in _] |- _ ] =>
      let n := fresh n in
      let m := fresh m in
      destruct a as [m n]; simpl in H
    | [ |- context[let (n, m) := ?a in _] ] =>
      let n := fresh n in
      let m := fresh m in
      destruct a as [m n]; simpl
    end.

  Section GetAttrCleanSpec.

    Hint Extern 0 {{ OptFS.file_get_attr _ _ _ _ _; _ }} => apply OptFS.file_get_attr_ok : prog.

    Theorem file_get_attr1_ok : forall inum tid mscs,
        cprog_spec fs_guarantee tid
                   (fun '(F, vd0, vd, tree, pathname, f) '(sigma_i, sigma) =>
                      {| precondition :=
                           (F * CacheRep CP (Sigma.disk sigma)
                                         empty_writebuffer vd0 vd)%pred (Sigma.mem sigma) /\
                           fs_rep vd (Sigma.hm sigma) mscs tree /\
                           find_subtree pathname tree = Some (TreeFile inum f);
                         postcondition :=
                           fun '(sigma_i', sigma') '(r, wb') =>
                             exists vd',
                               (F * CacheRep CP (Sigma.disk sigma') wb' vd0 vd')%pred (Sigma.mem sigma') /\
                               match r with
                               | Success (mscs', (r, _)) =>
                                 r = BFILE.BFAttr f /\
                                 fs_rep vd' (Sigma.hm sigma') mscs' tree
                               | Failed =>
                                 fs_rep vd (Sigma.hm sigma') mscs tree
                               end /\
                               sigma_i' = sigma_i
                      |}) (OptFS.file_get_attr CP fsxp inum mscs empty_writebuffer).
    Proof.
      intros.
      step.

      unfold OptFS.framed_spec, translate_spec; simpl.
      repeat apply exists_tuple.
      repeat break_tuple; simpl in *.
      unfold fs_rep in *; SepAuto.destruct_lifts; intuition;
        repeat (deex || SepAuto.destruct_lifts).

      descend; intuition eauto.
      SepAuto.pred_apply; SepAuto.cancel; eauto.

      step.
      repeat break_tuple; simpl in *; intuition;
        repeat deex.

      destruct a; simpl in *.
      - (* translated code returned success *)
        repeat break_tuple.
        unfold Prog.pair_args_helper in *.
        SepAuto.destruct_lifts; intuition eauto.
        descend; intuition eauto.
      - (* applying eauto strategically is much faster *)
        descend; intuition idtac.
        eauto.
        descend; intuition idtac.
        eapply LOG.rep_hashmap_subset; eauto.
        eauto.
    Qed.

  End GetAttrCleanSpec.

  Hint Extern 0 {{ OptFS.file_get_attr _ _ _ _ _; _ }} => apply file_get_attr1_ok : prog.

  Hint Extern 0 {{ CacheCommit _ _; _ }} => apply CacheCommit_ok : prog.
  Hint Extern 0 {{ CacheAbort; _ }} => apply CacheAbort_ok : prog.

  Hint Extern 0 (SepAuto.okToUnify
                   (CacheRep ?P ?d ?wb _ _)
                   (CacheRep ?P ?d ?wb _ _)) => constructor : okToUnify.

  Ltac simplify :=
    repeat match goal with
           | _ => break_tuple
           | _ => deex
           | [ H: _ /\ _ |- _ ] => destruct H
           | [ H: Sigma.disk _ = Sigma.disk _ |- _ ] =>
             progress rewrite H in *
           | [ H: Sigma.hm _ = Sigma.hm _ |- _ ] =>
             progress rewrite H in *
           | [ H: Success _ = Success _ |- _ ] =>
             inversion H; subst; clear H
           | [ H: Failed = Success _ |- _ ] =>
             exfalso; inversion H
           | _ => progress SepAuto.destruct_lifts
           | _ => progress simpl in *
           | _ => progress subst
           end.

  Ltac finish :=
    repeat match goal with
           | [ |- cprog_ok _ _ _ _ ] => fail 1
           | [ |- Rely _ _ _ ] => etransitivity; [ solve [ eauto ] | ]
           | [ |- fs_guarantee _ _ _ ] => eapply fs_guarantee_trans; [ solve [ eauto ] | ]
           | [ |- fs_invariant _ _ _ _ _ ] => unfold fs_invariant
           | [ |- Rely _ ?tid ?sigma ?sigma ] => try (is_evar tid; instantiate (1 := 0));
                                       reflexivity
           | [ |- ?g ] => solve [ first [ has_evar g | reflexivity ] ]
           | [ |- exists _, _ ] => descend; simpl
           | [ |- (_ * _)%pred _ ] => solve [ SepAuto.pred_apply; SepAuto.cancel ]
           | [ |- _ /\ _ ] => progress intuition eauto
           | _ => progress repeat match goal with
                                 | [ H: Sigma.disk _ = Sigma.disk _ |- _ ] =>
                                   rewrite H in *
                                 | [ H: Sigma.hm _ = Sigma.hm _ |- _ ] =>
                                   rewrite H in *
                                 end
           end.

  Ltac step := CCLAutomation.step; simplify; finish.

  Theorem file_get_attr_ok : forall inum tid,
      cprog_spec fs_guarantee tid
                 (fun '(tree, homedirs, pathname, f) '(sigma_i, sigma) =>
                    {| precondition :=
                         (fs_invariant (Sigma.disk sigma) (Sigma.hm sigma) tree homedirs) (Sigma.mem sigma) /\
                         find_subtree (homedirs tid ++ pathname) tree = Some (TreeFile inum f) /\
                         fs_guarantee tid sigma_i sigma;
                       postcondition :=
                         fun '(sigma_i', sigma') r =>
                           exists tree',
                             Rely fs_guarantee tid sigma sigma' /\
                             (fs_invariant (Sigma.disk sigma') (Sigma.hm sigma') tree' homedirs) (Sigma.mem sigma') /\
                             fs_guarantee tid sigma_i' sigma' /\
                             match r with
                             | Success (r, _) => r = BFILE.BFAttr f
                             | Failed => True
                             end
                    |}) (file_get_attr inum).
  Proof.
    unfold file_get_attr, retry_syscall; intros.

    eapply retry_spec' with Failed; induction n; simpl.
    - step.
      step.
    - unfold fs_invariant in *.
      step.
      step.

      destruct a as [(mscs & (attr & u)) | ].
      + step.
        step.
        step.
        step.

        destruct (guard r); simplify.
        step.

        eapply fs_rely_sametree; finish.
        unfold fs_guarantee; finish.

        step.
      + step.
        step.
        unfold fs_guarantee; finish.

        CCLAutomation.step; simplify.
        assert (fs_invariant (Sigma.disk sigma'0) (Sigma.hm sigma'0)
                             tree homedirs (Sigma.mem sigma'0)) by finish.
        lazymatch goal with
        | [ H: Rely _ _ ?sigma ?sigma' |- _ ] =>
          pose proof (fs_rely_invariant' H ltac:(eauto))
        end.
        simplify; finish.
        eapply fs_rely_preserves_subtree; eauto.
        simplify; eauto.

        eapply fs_guarantee_refl.
        eapply fs_rely_invariant; eauto.
        finish.

        step.
        etransitivity; eauto.
        etransitivity; eauto.
        eapply fs_rely_sametree; finish.
  Qed.

End ConcurrentFS.

(* Local Variables: *)
(* company-coq-local-symbols: (("Sigma" . ?Σ) ("sigma" . ?σ) ("sigma'" . (?σ (Br . Bl) ?'))) *)
(* End: *)