Require Import Word.
Require Import Omega.
Require Import Bool.
Require Import Pred.
Require Import PermDirCache.
Require Import PermGenSepN.
Require Import ListPred.
Require Import PermInode.
Require Import List ListUtils.
Require Import Bytes.
Require Import DirTree.
Require Import Rec.
Require Import Arith.
Require Import FSLayout.
Require Import Errno.
Require Import SuperBlock.
Require Import Lia.
Require Import FunctionalExtensionality.
Require Import PermBFile.
Require Import DirTreeDef.
Require Import DirTreeRep.
Require Import DirTreePred.
Require Import DirTreeInodes.
Require Import DirTreeSafe.
Require Import DirTreeNames.
Require Import DirTree.
Require Import AsyncFS AsyncFSPost AsyncFSProg.
Require Import FMapAVL.
Require Import FMapFacts.
Require Import AsyncFSDiskSec.

Set Implicit Arguments.
Import DIRTREE.
Import AFS.
Import ListNotations.

Notation MSLL := BFILE.MSLL.
Notation MSAllocC := BFILE.MSAllocC.
Notation MSIAllocC := BFILE.MSIAllocC.
Notation MSICache := BFILE.MSICache.
Notation MSAlloc := BFILE.MSAlloc.
Notation MSDBlocks := BFILE.MSDBlocks.

Lemma bind_orp:
  forall T T' (p1: prog T) (p2: T -> prog T') pr d bm hm,
    only_reads_permitted pr p1 d bm hm ->
    (forall tr d' bm' hm' r tr',
       exec pr tr d bm hm p1 (Finished d' bm' hm' r) tr' ->
       only_reads_permitted pr (p2 r) d' bm' hm') ->
    only_reads_permitted pr (Bind p1 p2) d bm hm.
Proof.
  simpl; intros.
  split; eauto.
Qed.

Lemma if_orp:
  forall P Q T (p1 p2: prog T) d bm hm pr (cond: {P}+{Q}),
    (forall l, cond = left l -> only_reads_permitted pr p1 d bm hm) ->
    (forall r, cond = right r -> only_reads_permitted pr p2 d bm hm) ->
    only_reads_permitted pr (If cond {p1} else {p2}) d bm hm.
Proof.
  intros; unfold If_.
  destruct cond eqn:D; simpl; eauto.
Qed.

Lemma forn_orp:
  forall  n (L : Type) (G : Type) (f : nat -> L -> prog L)
      i (nocrash : G -> nat -> L -> block_mem -> hashmap -> rawpred)
      (crashed : G -> block_mem -> hashmap -> rawpred) (l : L) pr d bm hm,
    only_reads_permitted pr (f i l) d bm hm ->
    (forall i l d bm hm d' bm' hm' r tr tr',
       exec pr tr d bm hm (f i l) (Finished d' bm' hm' r) tr' ->
       only_reads_permitted pr (f (S i) r) d' bm' hm') ->
    only_reads_permitted pr (ForN_ f i n nocrash crashed l) d bm hm.
Proof.
  induction n; intros.
  simpl; auto.
  simpl.
  split; intros; eauto.
Qed.



Lemma LOG_begin_orp:
  forall pr a b d bm hm,
    only_reads_permitted pr (LOG.begin a b) d bm hm.
Proof.
  intros.
  Transparent LOG.begin.
  unfold LOG.begin; simpl; auto.
Qed.

Lemma writeback_orp:
  forall pr a b d bm hm,
    only_reads_permitted pr (writeback a b) d bm hm.
Proof.
  unfold writeback; simpl; intros.
  destruct (MapUtils.AddrMap.Map.find a (CSMap b)); simpl; auto.
  destruct p; simpl; auto.
  destruct b0; simpl; auto.
Qed.

Hint Resolve LOG_begin_orp writeback_orp.

Lemma maybe_evict_orp:
  forall pr a d bm hm,
    only_reads_permitted pr (maybe_evict a) d bm hm.
Proof.
  unfold maybe_evict; simpl; intros.
  destruct (lt_dec (CSCount a) (CSMaxCount a)); simpl; auto.
  destruct (MapUtils.AddrMap.Map.find 0 (CSMap a)); simpl; auto.
  intuition; simpl.
  destruct (MapUtils.AddrMap.Map.find 0 (CSMap r)); simpl; auto.
  destruct (MapUtils.AddrMap.Map.elements (CSMap a)); simpl; auto.
  destruct p; simpl; auto.
  intuition.
  destruct (MapUtils.AddrMap.Map.find k (CSMap r)); simpl; auto.
Qed.

Hint Resolve maybe_evict_orp.



Lemma PermCacheDef_read_orp:
  forall Fr pr a cs dx d bm hm v,
    (Fr * [[ sync_invariant Fr ]] * PermCacheDef.rep cs dx bm)%pred d ->
    can_access pr (fst (fst v)) ->
    dx a = Some v ->
    only_reads_permitted pr (PermCacheDef.read a cs) d bm hm.
Proof.
  intros; unfold PermCacheDef.read; simpl.
  destruct (MapUtils.AddrMap.Map.find a (CSMap cs)) eqn:D; simpl; auto.
  destruct p; simpl; auto.
  intuition; simpl.   
  pose proof (maybe_evict_post H H2) as Hspec.
  destruct_lift Hspec.
  specialize H8 with (1:=D).
  unfold PermCacheDef.rep in *.
  rewrite mem_pred_extract in H4; eauto.
  unfold cachepred at 2 in H4.
  rewrite H8 in H4.
  repeat rewrite sep_star_assoc in H4.
  apply sep_star_assoc in H4.
  apply sep_star_assoc in H4.
  apply sep_star_assoc in H4.
  eapply ptsto_subset_valid' in H4.
  simpl in *; cleanup; eauto.
Qed.



Lemma MLog_read_orp:
  forall vs F pr d bm hm Fr a ms na xp ds,
    (Fr * [[ sync_invariant Fr ]] *
     exists raw, PermCacheDef.rep (snd ms) raw bm *
     [[ (F * MLog.rep xp (MLog.Synced na ds) (fst ms) bm hm)%pred raw ]] *
     [[[ ds ::: exists F', (F' * a |-> vs) ]]])%pred d ->
    can_access pr (fst (fst vs)) ->
    only_reads_permitted pr (MLog.read xp a ms) d bm hm.
Proof.
  intros; unfold MLog.read.
  destruct (MapUtils.AddrMap.Map.find a (MLog.MSInLog ms)) eqn:D; simpl; auto.
  intuition.
  destruct_lift H.
  denote MLog.rep as Hx; unfold MLog.rep, MLog.synced_rep in Hx.
  destruct_lift Hx.
  unfold LogReplay.map_replay in *.
  eapply map_find_In_elements_none in D.
  cleanup.
  eapply LogReplay.replay_disk_none_selN in D.
  2: pred_apply' H5; cancel.
  apply sep_star_comm in H1.
  apply sep_star_assoc in H1.
  eapply arrayN_selN_subset in H1.
  cleanup.
  eapply PermCacheDef_read_orp; eauto.
  pred_apply; cancel.
  setoid_rewrite H3.
  rewrite minus_plus.
  rewrite D; simpl; auto.
  omega.
  apply list2nmem_inbound in H5.
  rewrite LogReplay.replay_disk_length in H5.
  omega.
  Unshelve.
  exact valuset0.
Qed.

Lemma GLog_read_orp:
    forall vs F pr d bm hm Fr a ms xp ds,
    (Fr * [[ sync_invariant Fr ]] *
     exists raw, PermCacheDef.rep (snd ms) raw bm *
     [[ (F * GLog.rep xp (GLog.Cached ds) (fst ms) bm hm)%pred raw ]] *
     [[[ ds!! ::: exists F', (F' * a |-> vs) ]]])%pred d ->
    can_access pr (fst (fst vs)) ->
    only_reads_permitted pr (GLog.read xp a ms) d bm hm.
  Proof.
    intros; unfold GLog.read.
    destruct (MapUtils.AddrMap.Map.find a (GLog.MSVMap (fst ms))) eqn:D.
    simpl; auto.
    simpl; intuition.
    denote GLog.rep as Hx.
    unfold GLog.rep in Hx; destruct_lift Hx.
    eapply list2nmem_inbound in H5 as Hlen.
    erewrite <- GLog.latest_effective in H5; eauto.
    eapply GLog.diskset_vmap_find_none in D as Hx; eauto.
    erewrite GLog.dset_match_nthd_effective_fst in H2; eauto.
    eapply MLog_read_orp; eauto.
    pred_apply; cancel.
    eexists.
    apply list2nmem_array_pick.
    eapply GLog.diskset_ptsto_bound_effective; eauto.
    erewrite <- GLog.latest_effective; eauto.
    setoid_rewrite Hx; simpl; auto.
  Qed.


Lemma LOG_read_orp:
  forall pr d bm hm lxp a Fr ds dx sm ms Ftop vs,
    (Fr * [[ sync_invariant Fr ]] *
     LOG.rep lxp Ftop (LOG.ActiveTxn ds dx) ms sm bm hm *
     [[[ ds!! ::: exists F', (F' * a |-> vs) ]]])%pred d ->
    can_access pr (fst (fst vs)) ->
    only_reads_permitted pr (LOG.read lxp a ms) d bm hm.
Proof.
  intros; unfold LOG.read.
  destruct (MapUtils.AddrMap.Map.find a (LOG.MSTxn (fst ms))) eqn:D.
  simpl; auto.
  simpl; auto; intuition.
  denote LOG.rep as Hx.
  unfold LOG.rep, LOG.rep_inner in Hx. destruct_lift Hx.
  eapply GLog_read_orp; eauto.
  pred_apply; cancel.
  simpl; auto.
Qed.


Theorem INODE_IRec_get_orp:
forall Fr Fm F m sm items ms cache ix xp lxp pr d bm hm,
  (Fr * [[ sync_invariant Fr ]] *
   LOG.rep lxp F (LOG.ActiveTxn m m!!) ms sm bm hm *
   [[ ix < length items ]] *
   [[[ m!! ::: Fm * INODE.IRec.rep xp items cache ]]])%pred d ->
  only_reads_permitted pr (INODE.IRec.get lxp xp ix cache ms) d bm hm.
Proof.
  intros; unfold INODE.IRec.get; simpl; intuition.
  destruct (INODE.IRec.Cache.find ix cache) eqn:D;
  setoid_rewrite D; simpl; intuition.
  unfold INODE.IRec.rep, INODE.IRec.LRA.rep in *.
  destruct_lift H.
  
  eapply arrayN_selN with (a:= (INODE.IRecSig.RAStart xp + ix / INODE.IRecSig.items_per_val)) in H0 as Hx; try omega.
  rewrite minus_plus in Hx.
  setoid_rewrite synced_list_selN in Hx.
  setoid_rewrite selN_combine in Hx.
  rewrite repeat_selN in Hx.
  erewrite list2nmem_sel_inb in Hx.
  cleanup.
  erewrite <- LogReplay.replay_disk_empty with (d:= m!!)in H0; eauto. 
  eapply LOG_read_orp; eauto.
  pred_apply; cancel.
  eexists; eapply list2nmem_ptsto_cancel.
  eapply LOG.write_range_length_ok; eauto.
  rewrite synced_list_length;
  setoid_rewrite combine_length_eq; rewrite repeat_length; eauto.
  rewrite INODE.IRec.LRA.Defs.ipack_length; apply Rounding.div_lt_divup; eauto.
  apply INODE.IRec.Defs.items_per_val_not_0.
  rewrite H2; simpl; auto.
  apply AddrMap.Map.empty_1.
  erewrite <- LogReplay.replay_disk_empty with (d:= m!!)in H0; eauto.
  eapply LOG.write_range_length_ok; eauto.
  rewrite synced_list_length;
  setoid_rewrite combine_length_eq; rewrite repeat_length; eauto.
  rewrite INODE.IRec.LRA.Defs.ipack_length; apply Rounding.div_lt_divup; eauto.
  apply INODE.IRec.Defs.items_per_val_not_0.
  apply AddrMap.Map.empty_1.
  rewrite INODE.IRec.LRA.Defs.ipack_length; apply Rounding.div_lt_divup; eauto.
  apply INODE.IRec.Defs.items_per_val_not_0.
  apply repeat_length.
  rewrite synced_list_length;
  setoid_rewrite combine_length_eq; rewrite repeat_length; eauto.
  apply plus_lt_compat_l;  rewrite INODE.IRec.LRA.Defs.ipack_length;
  apply Rounding.div_lt_divup; eauto.
  apply INODE.IRec.Defs.items_per_val_not_0.

  Unshelve.
  exact Public.
  exact $0.
  exact valuset0.
Qed.

Theorem DIRTREE_getowner_orp:
forall Fr Fm Ftop ds sm pathname f tree mscs fsxp ilist frees pr inum d bm hm,
  (Fr * [[ sync_invariant Fr ]] *
     LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.ActiveTxn ds ds!!) (MSLL mscs) sm bm hm *
      [[[ ds!! ::: (Fm * rep fsxp Ftop tree ilist frees mscs sm)]]] *
      [[ find_subtree pathname tree = Some (TreeFile inum f) ]])%pred d ->
  only_reads_permitted pr (DIRTREE.getowner fsxp inum mscs) d bm hm.
Proof.
  intros; unfold getowner; simpl; intuition.
  unfold rep, BFILE.rep, INODE.rep in *; destruct_lift H.
  eapply INODE_IRec_get_orp; eauto.
  pred_apply; cancel.
  rewrite listmatch_length_pimpl in H0; destruct_lift H0.
  rewrite listmatch_length_pimpl with (a:= dummy) in H0; destruct_lift H0.
  setoid_rewrite <- H15.
  rewrite subtree_extract in H8; eauto.
  unfold tree_pred in H8; simpl in *.
  destruct_lift H8.
  rewrite combine_length_eq; eauto.
  setoid_rewrite <- H16.
  eapply list2nmem_inbound; pred_apply; cancel.
Qed.


Theorem INODE_getbnum_orp:
forall Fr Fm F Fi ino lxp xp IFs bxp m sm ilist pr inum cache ms d bm hm off,
  (Fr * [[ sync_invariant Fr ]] *
     LOG.rep lxp F (LOG.ActiveTxn m m!!) ms sm bm hm *
     [[ off < length (INODE.IBlocks ino) ]] *
     [[[ m!! ::: (Fm * INODE.rep bxp IFs xp ilist cache) ]]] *
     [[[ ilist ::: (Fi * inum |-> ino) ]]])%pred d ->
  only_reads_permitted pr (INODE.getbnum lxp xp inum off cache ms) d bm hm.
Proof.
  intros; unfold INODE.getbnum.
  apply bind_orp; intros.
  simpl; intuition.
  unfold INODE.rep in *.
  destruct_lift H.
  eapply INODE_IRec_get_orp; eauto.
  pred_apply; cancel.
  rewrite listmatch_length_pimpl in H1; destruct_lift H1.
  setoid_rewrite <- H8.
  rewrite combine_length_eq; eauto.
  eapply list2nmem_inbound; eauto.

  simpl; intuition.
  (** extract postcondition for INODE.IRec.get_array **)
  admit.
Admitted.


Theorem DIRTREE_dwrite_orp:
forall Fr Fm Ftop Fd vs ds sm pathname f tree mscs fsxp ilist frees pr inum d bm hm off h,
  (Fr * [[ sync_invariant Fr ]] *
     LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.ActiveTxn ds ds!!) (MSLL mscs) sm bm hm *
      [[[ ds!! ::: (Fm * rep fsxp Ftop tree ilist frees mscs sm)]]] *
      [[ find_subtree pathname tree = Some (TreeFile inum f) ]] *
      [[[ (DFData f) ::: (Fd * off |-> vs) ]]])%pred d ->
  only_reads_permitted pr (DIRTREE.dwrite fsxp inum off h mscs) d bm hm.
Proof.
  intros; unfold dwrite.
  apply bind_orp; [|simpl; intuition].
  unfold BFILE.dwrite.
  apply bind_orp; intros.

  unfold rep, BFILE.rep in *; destruct_lift H.
  eapply INODE_getbnum_orp; eauto.
  pred_apply; cancel.
Abort.

Lemma PermDiskLogHdr_read_orp:
  forall Fr F pr cs dx d bm hm xp n,
    (Fr * [[ sync_invariant Fr ]] * PermCacheDef.rep cs dx bm *
    [[ (F * PermDiskLogHdr.rep xp (PermDiskLogHdr.Synced n))%pred dx ]])%pred d ->
    only_reads_permitted pr (PermDiskLogHdr.read xp cs) d bm hm.
Proof.
  intros; unfold PermDiskLogHdr.read.
  apply bind_orp; intros; [|simpl; intuition].
  unfold PermDiskLogHdr.rep in H.
  destruct_lift H.
  apply ptsto_subset_valid' in H1; cleanup.
  simpl in *.
  eapply PermCacheDef_read_orp; eauto.
  pred_apply; cancel.
  simpl; auto.
Qed.

Lemma GLog_submit_orp:
  forall pr d bm hm a b c,
    only_reads_permitted pr (GLog.submit a b c) d bm hm.
Proof.
  intros; unfold GLog.submit.
  apply if_orp; intros; simpl; auto.
Qed.

Hint Resolve GLog_submit_orp.


Lemma foreach_orp:
  forall  (ITEM : Type) (lst : list ITEM)
       (L : Type) (G : Type) (f : ITEM -> L -> prog L)        
       (nocrash : G -> list ITEM -> L -> block_mem -> hashmap -> rawpred)
       (crashed : G -> block_mem -> hashmap -> rawpred) (l : L) d bm hm pr,
    (forall a lst', lst = a::lst' -> only_reads_permitted pr (f a l) d bm hm) ->
    (forall i j l d bm hm d' bm' hm' r tr tr',
       exec pr tr d bm hm (f i l) (Finished d' bm' hm' r) tr' ->
       only_reads_permitted pr (f j r) d' bm' hm') ->
    only_reads_permitted pr (ForEach_ f lst nocrash crashed l) d bm hm.
Proof.
  induction lst; intros.
  simpl; auto.
  simpl.
  split; intros; eauto.
Qed.

Lemma LOG_commit_orp:
  forall pr d bm hm lxp Fr ds dx sm ms Ftop,
    (Fr * [[ sync_invariant Fr ]] *
     LOG.rep lxp Ftop (LOG.ActiveTxn ds dx) ms sm bm hm)%pred d ->
    only_reads_permitted pr (LOG.commit lxp ms) d bm hm.
Proof.
  Transparent LOG.commit.
  intros; unfold LOG.commit.
  apply bind_orp; intros; auto.
  (** extract GLog.submit postcondition **)
  apply if_orp; intros; simpl; intuition.
  { (** GLog.flushall **)
    unfold GLog.flushall.
    apply if_orp; intros.
    apply bind_orp; simpl; auto.
    { (** MLog.flush **)
      unfold MLog.flush.
      apply if_orp; intros; [simpl; intuition|].
      apply bind_orp; intros.
      { (** PermDiskLog.avail **)
        unfold avail.
        apply bind_orp; intros; [|simpl; auto].
        unfold PermDiskLogPadded.avail.
        apply bind_orp; intros; [|simpl; auto].
        denote LOG.rep as Hx; unfold LOG.rep, LOG.rep_inner,
        GLog.rep, MLog.rep, PermDiskLog.rep,
        PermDiskLogPadded.rep, rep_inner in Hx.
        admit. (** Reading header so it is public **)
        destruct r1, p, p, p, p, p0, p1; simpl; auto.
      }
      apply bind_orp; intros.
      apply if_orp; intros; [|simpl; intuition].
      apply bind_orp; intros; [|simpl; auto].
      { (** MLog.apply **)
        unfold MLog.apply.
        apply bind_orp; intros.
        simpl; intuition.
        apply forn_orp; intros; simpl; intuition.
        destruct (MapUtils.AddrMap.Map.find
        (DataStart lxp +
         fst (selN (MapUtils.AddrMap.Map.elements
         (GLog.MSMLog (fst (fst r)))) 0 (0, 0)))
        (CSMap r2)) eqn:D; setoid_rewrite D; simpl; auto.
        destruct (MapUtils.AddrMap.Map.find
        (DataStart lxp +
         fst (selN (MapUtils.AddrMap.Map.elements
         (GLog.MSMLog (fst (fst r)))) (S i) (0, 0)))
        (CSMap r3)) eqn:D; setoid_rewrite D; simpl; auto.
        apply bind_orp; intros.
        simpl; intuition.
        apply foreach_orp; intros; simpl; intuition.
        apply bind_orp; intros; [|simpl; auto].
        { (** LOG.trunc **)
          unfold trunc.
          apply bind_orp; intros; [|simpl; auto].
          unfold PermDiskLogPadded.trunc.
          apply bind_orp; intros; [|simpl; intuition].
          admit. (** Reading header so it is public **)
          destruct r4, p, p, p, p, p0, p1; simpl; intuition.
          destruct (MapUtils.AddrMap.Map.find (LAHdr lxp) (CSMap r6));
          simpl; auto.
        }
      }
      apply bind_orp; intros; [|simpl; auto].
      { (** MLog.flush_noapply **)
        unfold MLog.flush_noapply.
        apply bind_orp; intros; [|apply if_orp; intros; simpl; auto].
        { (** PermDiskLog.extend **)
          unfold extend.
          apply bind_orp; intros; [|simpl; auto].
          unfold PermDiskLogPadded.extend.
          apply bind_orp; intros; [|simpl; auto].
          admit. (** Reading header so it is public **)
          destruct r3, p, p, p, p, p0, p1; simpl; intuition.
          apply if_orp; intros.
          apply bind_orp; intros.
          simpl; intuition.
          apply forn_orp; intros; simpl; intuition.
          apply bind_orp; intros.
          simpl; intuition.
          apply foreach_orp; intros; simpl; intuition.
          apply bind_orp; intros.
          simpl; intuition.
          apply foreach_orp; intros; simpl; intuition.
          apply bind_orp; intros.
          simpl; intuition.
          apply forn_orp; intros; simpl; intuition.
          destruct (MapUtils.AddrMap.Map.find
                      (DescSig.RAStart lxp + n1 + 0) (CSMap r6));
          simpl; auto.
          destruct (MapUtils.AddrMap.Map.find
                      (DescSig.RAStart lxp + n1 + S i) (CSMap r7));
          simpl; auto.
          apply bind_orp; intros.
          simpl; intuition.
          apply forn_orp; intros; simpl; intuition.
          destruct (MapUtils.AddrMap.Map.find
                      (DataSig.RAStart lxp + n2 + 0) (CSMap r7));
          simpl; auto.
          destruct (MapUtils.AddrMap.Map.find
                      (DataSig.RAStart lxp + n2 + S i) (CSMap r8));
          simpl; auto.
          apply bind_orp; intros.
          simpl; intuition.
          destruct (MapUtils.AddrMap.Map.find (LAHdr lxp) (CSMap r9));
          simpl; auto.
          apply bind_orp; intros.
          simpl; auto.
          apply bind_orp; intros.
          simpl; intuition.
          apply forn_orp; intros; simpl; intuition.
          apply bind_orp; intros.
          simpl; intuition.
          apply forn_orp; intros; simpl; intuition.
          apply bind_orp; intros.
          simpl; intuition.
          apply bind_orp; intros; simpl; auto.
          simpl; auto.
        }
      }
    }
    apply bind_orp; intros; [|simpl; auto].
    { (** GLog.flushall_nomerge **)
      unfold GLog.flushall_nomerge.
      apply bind_orp; intros; [|simpl; auto].
      simpl; intuition.
      apply forn_orp; intros; simpl; intuition.
      admit. (** MLog.flush **)
      admit. (** MLog.flush **)
    }
  }
Admitted.

