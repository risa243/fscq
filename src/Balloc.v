Require Import Arith.
Require Import Pred.
Require Import Word.
Require Import Prog.
Require Import Hoare.
Require Import SepAuto.
Require Import BasicProg.
Require Import Omega.
Require Import Array.
Require Import List.
Require Import Bool.
Require Import Nomega.
Require Import Idempotent.
Require Import Psatz.
Require Import AddrMap.
Require Import Rec.
Require Import NArith.
Require Import MemLog.
Require Import RecArray.
Require Import ListPred.
Require Import GenSep.
Require Import WordAuto.
Require Import FSLayout.


Set Implicit Arguments.


(* Block allocator *)

Module BALLOC.

  Definition itemtype := Rec.WordF 1.
  Definition items_per_valu : addr := natToWord addrlen valulen.

  Theorem blocksz : valulen = Rec.len (RecArray.blocktype itemtype items_per_valu).
  Proof.
    unfold blocktype, items_per_valu.
    rewrite wordToNat_natToWord_idempotent.
    simpl. ring.
    rewrite valulen_is. compute. auto.
  Qed.

  Definition rep_block := RecArray.rep_block blocksz.
  Definition valu_to_block := RecArray.valu_to_block itemtype items_per_valu blocksz.
  Definition rep_valu_id := RecArray.rep_valu_id blocksz.


  Inductive alloc_state :=
  | Avail
  | InUse.

  Definition alloc_state_dec : forall (a b : alloc_state), {a = b} + {a <> b}.
    destruct a; destruct b; try (left; constructor); right; discriminate.
  Defined.

  Definition alloc_state_to_bit a : word 1 :=
    match a with
    | Avail => $0
    | InUse => $1
    end.

  Definition bit_to_alloc_state (b : word 1) : alloc_state :=
    if weq b $0 then Avail else InUse.

  Lemma bit_alloc_state_id : forall a, bit_to_alloc_state (alloc_state_to_bit a) = a.
  Proof.
    destruct a; auto.
  Qed.
  Hint Rewrite bit_alloc_state_id.

  Definition valid_block xp bn := (bn < BmapNBlocks xp ^* $ valulen)%word.

  Definition bmap_bits xp (bmap : addr -> alloc_state) :=
     map (fun i => alloc_state_to_bit (bmap $ (i)))
          (seq 0 (wordToNat (BmapNBlocks xp) * valulen)).

  Definition xp_to_raxp xp :=
    RecArray.Build_xparams (BmapStart xp) (BmapNBlocks xp).

  Definition rep' xp (bmap : addr -> alloc_state) :=
    ([[ goodSize addrlen (wordToNat (BmapNBlocks xp) * valulen) ]] *
     RecArray.array_item itemtype items_per_valu blocksz (xp_to_raxp xp)
       (bmap_bits xp bmap))%pred.

  Definition free' T lxp xp bn mscs rx : prog T :=
    mscs <- RecArray.put itemtype items_per_valu blocksz
      lxp (xp_to_raxp xp) bn (alloc_state_to_bit Avail) mscs;
    rx mscs.

  Lemma selN_seq : forall a b c d, c < b -> selN (seq a b) c d = a + c.
  Proof.
    intros. rewrite nth_selN_eq. apply seq_nth; assumption.
  Qed.

  (* The third hypothesis isn't necessary but makes things simpler *)
  Lemma upd_bmap_bits : forall xp a bn b state,
    b = alloc_state_to_bit state ->
    goodSize addrlen (wordToNat (BmapNBlocks xp) * valulen) ->
    wordToNat bn < wordToNat (BmapNBlocks xp) * valulen ->
    upd (bmap_bits xp a) bn b = bmap_bits xp (fupd a bn state).
  Proof.
    intros. rewrite H. unfold bmap_bits, upd.
    rewrite updN_map_seq by assumption.
    eapply list_selN_ext with (default := $ (0)).
    repeat rewrite map_length; trivial.
    intros pos Hl.
    rewrite map_length in Hl. rewrite seq_length in Hl.
    repeat rewrite selN_map with (default' := 0) by (rewrite seq_length; assumption).
    rewrite selN_seq by assumption. simpl.
    destruct (Nat.eq_dec pos (wordToNat bn)).
    rewrite e. rewrite natToWord_wordToNat. rewrite fupd_same; trivial.
    rewrite fupd_other. trivial.
    eapply f_neq.
    rewrite wordToNat_natToWord_idempotent'.
    auto.
    eapply Nat.lt_trans. apply Hl.
    assumption.
  Qed.

  Theorem free'_ok : forall lxp xp mscs bn,
    {< Fm mbase m bmap,
    PRE
      MEMLOG.rep lxp (ActiveTxn mbase m) mscs *
      [[ (Fm * rep' xp bmap)%pred (list2mem m) ]] *
      [[ (bn < BmapNBlocks xp ^* $ valulen)%word ]]
    POST RET:mscs
      exists m', MEMLOG.rep lxp (ActiveTxn mbase m') mscs *
      [[ (Fm * rep' xp (fupd bmap bn Avail))%pred (list2mem m') ]]
    CRASH
      MEMLOG.log_intact lxp mbase
    >} free' lxp xp bn mscs.
  Proof.
    unfold free', rep', valid_block, MEMLOG.log_intact.
    hoare.
    erewrite upd_bmap_bits; try trivial.
    cancel.
    auto.
    word2nat_auto.
  Qed.

  Hint Extern 1 ({{_}} progseq (free' _ _ _ _) _) => apply free'_ok : prog.

  Definition alloc' T lxp xp mscs rx : prog T :=
    let^ (mscs) <- For i < (BmapNBlocks xp ^* $ (valulen))
      Ghost [ mbase m ]
      Loopvar [ mscs ]
      Continuation lrx
      Invariant
        MEMLOG.rep lxp (ActiveTxn mbase m) mscs
      OnCrash
        MEMLOG.log_intact lxp mbase
      Begin
        let^ (mscs, bit) <- RecArray.get itemtype items_per_valu blocksz
          lxp (xp_to_raxp xp) i mscs;
        let state := bit_to_alloc_state bit in
        If (alloc_state_dec state Avail) {
          mscs <- RecArray.put itemtype items_per_valu blocksz
            lxp (xp_to_raxp xp) i (alloc_state_to_bit InUse) mscs;
          rx ^(mscs, Some i)
        } else {
          lrx ^(mscs)
        }
      Rof ^(mscs);
    rx ^(mscs, None).

  Hint Rewrite natToWord_wordToNat selN_map_seq.



  Theorem alloc'_ok: forall lxp xp mscs,
    {< Fm mbase m bmap,
    PRE
      MEMLOG.rep lxp (ActiveTxn mbase m) mscs * [[ (Fm * rep' xp bmap)%pred (list2mem m) ]]
    POST RET:^(mscs,r)
      [[ r = None ]] * MEMLOG.rep lxp (ActiveTxn mbase m) mscs \/
      exists bn m', [[ r = Some bn ]] * [[ bmap bn = Avail ]] *
      MEMLOG.rep lxp (ActiveTxn mbase m') mscs *
      [[ (Fm * rep' xp (fupd bmap bn InUse))%pred (list2mem m') ]] *
      [[ valid_block xp bn ]]
    CRASH
      MEMLOG.log_intact lxp mbase
    >} alloc' lxp xp mscs.
  Proof.
    unfold alloc', rep'.
    hoare.
    apply pimpl_or_r; right.
    cancel.
    rewrite <- H9. unfold bmap_bits, sel.
    autorewrite with core; auto.
    word2nat_auto.
    erewrite upd_bmap_bits; trivial.
    cancel.
    auto.
    word2nat_auto.
  Qed.


  Hint Extern 1 ({{_}} progseq (alloc' _ _ _) _) => apply alloc'_ok : prog.


  Definition init' T lxp xp mscs rx : prog T :=
    let^ (mscs) <- For i < (BmapNBlocks xp)
      Ghost [ mbase F ]
      Loopvar [ mscs ]
      Continuation lrx
      Invariant
        exists m', MEMLOG.rep lxp (ActiveTxn mbase m') mscs *
        [[ goodSize addrlen (wordToNat i * valulen) ]] *
        [[ (F * RecArray.array_item itemtype items_per_valu blocksz
                (RecArray.Build_xparams (BmapStart xp) i)
                (map (fun _ => $0) (seq 0 (#i * valulen))))%pred (list2mem m') ]]
      OnCrash
        MEMLOG.log_intact lxp mbase
      Begin
        mscs <- MEMLOG.write_array lxp (BmapStart xp) i $1 $0 mscs;
        lrx ^(mscs)
      Rof ^(mscs);
    rx mscs.

  Definition bmap0 : addr -> alloc_state :=
    fun _ => Avail.

  Theorem init'_ok : forall lxp xp mscs,
    {< mbase m F,
    PRE
      exists a, MEMLOG.rep lxp (ActiveTxn mbase m) mscs *
      [[ (F * array (BmapStart xp) a $1)%pred (list2mem m) ]] *
      [[ length a = # (BmapNBlocks xp) ]] *
      [[ goodSize addrlen (# (BmapNBlocks xp) * valulen) ]]
    POST RET:mscs
      exists m', MEMLOG.rep lxp (ActiveTxn mbase m') mscs *
      [[ (F * rep' xp bmap0)%pred (list2mem m') ]]
    CRASH
      MEMLOG.log_intact lxp mbase
    >} init' lxp xp mscs.
  Proof.
    unfold init', rep'.
    step.
    rewrite <- roundTrip_0 with (sz:=addrlen); apply wordToNat_good.
    unfold array_item; cancel.
    instantiate (a:=nil); unfold array_item_pairs; cancel.
    reflexivity.

    step.
    rewrite H5. apply wlt_lt. auto.
    step.

    apply wlt_lt in H.
    unfold goodSize in *. eapply le_lt_trans; [|apply H4].
    replace (#(m0 ^+ $1)) with (#m0 + 1).
    apply mult_le_compat_r. omega.
    rewrite wplus_alt. unfold wplusN, wordBinN; simpl.
    erewrite wordToNat_natToWord_bound with (bound:=BmapNBlocks xp); omega.

    admit.
    unfold MEMLOG.log_intact; cancel.
    step.
    admit.
  Qed.

  Hint Extern 1 ({{_}} progseq (init' _ _ _) _) => apply init'_ok : prog.


  (* Different names just so that we can state another theorem about them *)
  Definition alloc_gen := alloc'.
  Definition free_gen := free'.

  Definition rep_gen V xp (freeblocks : list addr)
                          (genpred : @pred _ (@weq addrlen) V)
                          (genpredn : @pred _ eq_nat_dec V) :=
    (exists bmap,
     rep' xp bmap *
     [[ forall a, In a freeblocks <-> bmap a = Avail ]] *
     [[ genpred = listpred (fun a => a |->?) freeblocks ]] *
     [[ genpredn = listpred (fun a => #a |->?) freeblocks ]])%pred.

  Theorem alloc_gen_ok : forall V lxp xp mscs,
    {< Fm mbase m freeblocks genpred genpredn,
    PRE
      MEMLOG.rep lxp (ActiveTxn mbase m) mscs *
      [[ (Fm * @rep_gen V xp freeblocks genpred genpredn)%pred (list2mem m) ]]
    POST RET:^(mscs,r)
      [[ r = None ]] * MEMLOG.rep lxp (ActiveTxn mbase m) mscs \/
      exists bn m' freeblocks' genpred' genpredn', [[ r = Some bn ]] *
      MEMLOG.rep lxp (ActiveTxn mbase m') mscs *
      [[ (Fm * @rep_gen V xp freeblocks' genpred' genpredn')%pred (list2mem m') ]] *
      [[ genpred =p=> genpred' * bn |->? ]] *
      [[ genpredn =p=> genpredn' * #bn |->? ]] *
      [[ valid_block xp bn ]]
    CRASH
      MEMLOG.log_intact lxp mbase
    >} alloc_gen lxp xp mscs.
  Proof.
    unfold alloc_gen.
    intros.
    eapply pimpl_ok2. apply alloc'_ok.
    unfold rep_gen, rep'.
    cancel.
    step.
    apply pimpl_or_r. right.
    norm. (* We can't just [cancel] here because it introduces evars too early *)
    cancel.
    intuition.

    pred_apply.
    cancel.

    assert (a a0 = Avail) as Ha by ( apply H9; eapply remove_still_In; eauto ).
    rewrite <- Ha.
    apply fupd_other.
    eapply remove_still_In_ne; eauto.

    assert (a3 <> a0).
    intro He. subst. rewrite fupd_same in *. discriminate. trivial.
    rewrite fupd_other in * by assumption.
    apply remove_other_In. assumption.
    rewrite H9; assumption.

    erewrite listpred_remove with (dec := @weq addrlen). cancel.
    intros; apply ptsto_conflict.
    rewrite H9; assumption.

    erewrite listpred_remove with (dec := @weq addrlen). cancel.
    intros; apply ptsto_conflict.
    rewrite H9; assumption.
  Qed.

  Theorem free_gen_ok : forall V lxp xp bn mscs,
    {< Fm mbase m freeblocks genpred genpredn,
    PRE
      MEMLOG.rep lxp (ActiveTxn mbase m) mscs *
      [[ (Fm * @rep_gen V xp freeblocks genpred genpredn)%pred (list2mem m) ]] *
      [[ (bn < BmapNBlocks xp ^* $ valulen)%word ]]
    POST RET:mscs
      exists m' genpred' genpredn', MEMLOG.rep lxp (ActiveTxn mbase m') mscs *
      [[ (Fm * @rep_gen V xp (bn :: freeblocks) genpred' genpredn')%pred (list2mem m') ]] *
      [[ bn |->? * genpred =p=> genpred' ]] *
      [[ #bn |->? * genpredn =p=> genpredn' ]]
    CRASH
      MEMLOG.log_intact lxp mbase
    >} free_gen lxp xp bn mscs.
  Proof.
    unfold free_gen.
    intros.
    eapply pimpl_ok2. apply free'_ok.
    unfold rep_gen, rep'.
    cancel.
    step.
    subst; apply fupd_same; trivial.
    rewrite H10 in H3.
    destruct (weq bn a1).
    subst; apply fupd_same; trivial.
    rewrite <- H3; apply fupd_other; assumption.
    destruct (weq bn a1).
    left. auto.
    right. rewrite fupd_other in H0 by assumption. apply H10; assumption.
  Qed.

  Hint Extern 1 ({{_}} progseq (BALLOC.alloc_gen _ _ _) _) => apply BALLOC.alloc_gen_ok : prog.
  Hint Extern 1 ({{_}} progseq (BALLOC.free_gen _ _ _ _) _) => apply BALLOC.free_gen_ok : prog.
  Hint Extern 0 (okToUnify (rep_gen _ _ _ _) (rep_gen _ _ _ _)) => constructor : okToUnify.

  (* Different names for actual on-disk-block allocation *)
  Definition alloc := alloc_gen.
  Definition free := free_gen.

  Definition rep xp (freeblocks : list addr) :=
    (exists genpred genpredn, genpred * rep_gen xp freeblocks genpred genpredn)%pred.

  Theorem alloc_ok : forall lxp xp mscs,
    {< Fm mbase m freeblocks,
    PRE
      MEMLOG.rep lxp (ActiveTxn mbase m) mscs * [[ (Fm * rep xp freeblocks)%pred (list2mem m) ]]
    POST RET:^(mscs,r)
      [[ r = None ]] * MEMLOG.rep lxp (ActiveTxn mbase m) mscs \/
      exists bn m' freeblocks', [[ r = Some bn ]] *
      MEMLOG.rep lxp (ActiveTxn mbase m') mscs *
      [[ (Fm * bn |->? * rep xp freeblocks')%pred (list2mem m') ]] *
      [[ valid_block xp bn ]]
    CRASH
      MEMLOG.log_intact lxp mbase
    >} alloc lxp xp mscs.
  Proof.
    unfold alloc, rep.
    intros.
    eapply pimpl_ok2. apply alloc_gen_ok.
    cancel.
    step.
    rewrite H10 in H7.
    apply pimpl_or_r. right.
    cancel.
  Qed.

  Theorem free_ok : forall lxp xp bn mscs,
    {< Fm mbase m freeblocks,
    PRE
      MEMLOG.rep lxp (ActiveTxn mbase m) mscs *
      [[ (Fm * rep xp freeblocks * bn |->?)%pred (list2mem m) ]] *
      [[ (bn < BmapNBlocks xp ^* $ valulen)%word ]]
    POST RET:mscs
      exists m', MEMLOG.rep lxp (ActiveTxn mbase m') mscs *
      [[ (Fm * rep xp (bn :: freeblocks))%pred (list2mem m') ]]
    CRASH
      MEMLOG.log_intact lxp mbase
    >} free lxp xp bn mscs.
  Proof.
    unfold free, rep.
    intros.
    eapply pimpl_ok2. apply free_gen_ok.
    cancel.
    step.
  Qed.

  Hint Extern 1 ({{_}} progseq (BALLOC.alloc _ _ _) _) => apply BALLOC.alloc_ok : prog.
  Hint Extern 1 ({{_}} progseq (BALLOC.free _ _ _ _) _) => apply BALLOC.free_ok : prog.
  Hint Extern 0 (okToUnify (rep _ _) (rep _ _)) => constructor : okToUnify.

End BALLOC.
