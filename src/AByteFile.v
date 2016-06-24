Require Import Arith.
Require Import Pred PredCrash.
Require Import Word.
Require Import Prog ProgMonad.
Require Import Hoare.
Require Import SepAuto.
Require Import BasicProg.
Require Import Omega.
Require Import Log.
Require Import Array.
Require Import List ListUtils.
Require Import Bool.
Require Import Setoid.
Require Import Rec.
Require Import FunctionalExtensionality.
Require Import NArith.
Require Import WordAuto.
Require Import RecArrayUtils LogRecArray.
Require Import GenSepN.
Require Import Balloc.
Require Import ListPred.
Require Import FSLayout.
Require Import AsyncDisk.
Require Import Inode.
Require Import GenSepAuto.
Require Import DiskSet.
Require Import BFile.
Require Import Bytes.
Require Import NEList.
Require Import VBConv.

Set Implicit Arguments.

Module ABYTEFILE.

(* Definitions *)
Definition attr := INODE.iattr.
Definition attr0 := INODE.iattr0.



Record proto_bytefile := mk_proto_bytefile {
  PByFData : list (list byteset)
}.
Definition proto_bytefile0 := mk_proto_bytefile nil.

Record unified_bytefile := mk_unified_bytefile {
  UByFData : list byteset
}.
Definition unified_bytefile0 := mk_unified_bytefile nil.

Record bytefile := mk_bytefile {
  ByFData : list byteset;
  ByFAttr : INODE.iattr
}.
Definition bytefile0 := mk_bytefile nil attr0.

(* Helper Functions *)


Definition proto_bytefile_valid f pfy: Prop :=
(PByFData pfy) = map valuset2bytesets (BFILE.BFData f).

Definition unified_bytefile_valid pfy ufy: Prop := 
UByFData ufy = concat (PByFData pfy).

Definition bytefile_valid ufy fy: Prop :=
ByFData fy = firstn (length(ByFData fy)) (UByFData ufy).
  
Definition rep lxp bxp ixp flist ilist frees inum  F Fm Fi fms m0 m hm f fy :=
( exists pfy ufy, LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms) hm *
[[[ m ::: (Fm * BFILE.rep bxp ixp flist ilist frees) ]]] *
[[[ flist ::: (Fi * inum |-> f) ]]] *
[[ proto_bytefile_valid f pfy ]] *
[[ unified_bytefile_valid pfy ufy ]] *
[[ bytefile_valid ufy fy ]] * 
[[ # (INODE.ABytes (ByFAttr fy)) = length(ByFData fy)]])%pred .

Definition read_first_block lxp ixp inum fms block_off byte_off read_length :=
      let^ (fms, first_block) <- BFILE.read lxp ixp inum block_off fms;   (* get first block *)
      let data_init := (get_sublist (valu2list first_block) byte_off read_length) in
      Ret ^(fms, data_init).
      

Definition read_middle_blocks lxp ixp inum fms block_off num_of_full_blocks:=
let^ (data) <- (ForN_ (fun i =>
        (pair_args_helper (fun data (_:unit) => 
        
        let^ (fms, list) <- read_first_block lxp ixp inum fms (block_off + i) 0 valubytes;
        Ret ^(data++list)%list (* append its contents *)
        
        ))) 0 num_of_full_blocks
      
      (pair_args_helper (A:= log_xparams) (fun lxp =>
      (pair_args_helper (A:= INODE.IRecSig.xparams)(fun ixp =>
      (pair_args_helper (A:= addr)(fun inum =>
      (pair_args_helper (A:= BFILE.memstate)(fun fms => 
      (pair_args_helper (A:= addr)(fun block_off (_:unit) =>
      (fun i =>
      (pair_args_helper (fun (data: list byte) (_:unit) =>
      (fun hm =>  [[i = length data / valubytes]]))))))))))))))%pred (* trivial invariant *)
      
      
      (pair_args_helper (fun lxp =>
      (pair_args_helper (fun ixp =>
      (pair_args_helper (fun inum =>
      (pair_args_helper (fun fms => 
      (pair_args_helper (fun block_off (_:unit) =>
      (fun hm =>  [[True]]))))))))))))%pred ^(nil);             (* trivial crashpred *)
Ret ^(fms, data). 

(* let^ ((data:list byte)) <- ForN i < num_of_full_blocks 
            Ghost [  crash lxp ixp inum fms block_off ] 
            Loopvar [ (data:list byte) ] 
            Invariant [[i = length data / valubytes]] 
            OnCrash crash
            Begin
            let^ (fms, (block: valu)) <- BFILE.read lxp ixp inum (block_off + i) fms; (* get i'th block *)
            Ret ^(data++(valu2list block))%list (* append its contents *) 
            Rof ^((nil:list byte));
Ret ^(fms, data). *)



Definition read_last_block  lxp ixp inum fms block_off read_length :=
let^ (fms, list) <- read_first_block lxp ixp inum fms block_off 0 read_length;
Ret ^(fms, list).



(*Interface*)
Definition read lxp ixp inum off len fms :=
If (lt_dec 0 len)                        (* if read length > 0 *)
{                    
  let^ (fms, flen) <- BFILE.getlen lxp ixp inum fms;          (* get file length *)
  If (lt_dec off flen)                   (* if offset is inside file *)
  {                    
      let len := min len (flen - off) in
      let block_size := valubytes in            (* get block size *)
      let block_off := off / block_size in              (* calculate block offset *)
      let byte_off := off mod block_size in          (* calculate byte offset *)
      let first_read_length := min (block_size - byte_off) len in (*# of bytes that will be read from first block*)
      
      (*Read first block*)
      let^ (fms, data_first) <- read_first_block lxp ixp inum fms block_off byte_off first_read_length;   (* get first block *)
      
      let block_off := S block_off in
      let len_remain := (len - first_read_length) in  (* length of remaining part *)
      let num_of_full_blocks := (len_remain / block_size) in (* number of full blocks in length *)
      If (lt_dec 0 num_of_full_blocks)                        (* if read length > 0 *)
      {  
        (*for loop for reading full blocks in between*)
        let^ (fms, data_middle) <- read_middle_blocks lxp ixp inum fms block_off num_of_full_blocks;
        let off_final := (block_off + num_of_full_blocks) in (* offset of final block *)
        let len_final := (len_remain - num_of_full_blocks * block_size) in (* final remaining length *)
        If (lt_dec 0 len_final)
        {
          let^ (fms, data_last) <- read_last_block lxp ixp inum fms off_final len_final;
          Ret ^(fms, data_first++data_middle++data_last)%list  
        }
        else
        {
          Ret ^(fms, data_first++data_middle)%list  
        }
      }
      else
      {
        let off_final := (block_off + num_of_full_blocks) in (* offset of final block *)
        let len_final := (len_remain - num_of_full_blocks * block_size) in (* final remaining length *)
        If (lt_dec 0 len_final)
        {
          let^ (fms, data_last) <- read_last_block lxp ixp inum fms off_final len_final;
          Ret ^(fms, data_first++data_last)%list  
        }
        else
        {
          Ret ^(fms, data_first)%list  
        }
      }
  } 
  else                                                 (* if offset is not valid, return nil *)
  {    
    Ret ^(fms, nil)
  }
} 
else                                                   (* if read length is not valid, return nil *)
{    
  Ret ^(fms, nil)
}.

Definition write_first_block lxp ixp inum fms block_off byte_off data :=
 let^ (fms, first_block) <- BFILE.read lxp ixp inum block_off fms;   (* get first block *) 
    let first_block_list := valu2list first_block in
    let first_block_write := list2valu ((firstn byte_off first_block_list)     (* Construct first block*)
                              ++data++(skipn (byte_off + length data) first_block_list))%list in 
    (*Write first block*)                          
    let^ (ms, bn) <-INODE.getbnum lxp ixp inum block_off (BFILE.MSLL fms);
    ms <- LOG.write lxp (# bn) first_block_write ms;
Ret (fms).




Definition write_middle_blocks lxp ixp inum fms block_off num_of_full_blocks data:=
     let block_size := valubytes in
    let^ (temp) <- (ForN_ (fun i => (pair_args_helper (fun d (_:unit) =>
      
      fms <- write_first_block lxp ixp inum fms (block_off + i) 0 
                (get_sublist data (i*block_size) block_size);
      Ret ^(nil: list byte)
      
      ))) 0 num_of_full_blocks
    (fun _:nat => (fun _ => (fun _ => (fun _ => (fun _ => True)%pred)))) (* trivial invariant *)
    (fun _:nat => (fun _ => (fun _ => True)%pred))) ^(nil);             (* trivial crashpred *)
    Ret (fms).
    
    (* let^ ((data:list byte)) <- ForN i < num_of_full_blocks 
            Ghost [ lxp ixp inum fms block_off first_write_length num_of_full_blocks data ] 
            Loopvar [ (d:list byte) ] 
            Invariant [[True]] 
            OnCrash [[True]]
            Begin
              let^ (ms, bn) <- INODE.getbnum lxp ixp inum (block_off+i) (BFILE.MSLL fms);(* get i'th block number *)
              ms <- LOG.write lxp (# bn) (list2valu (get_sublist data (first_write_length + i*block_size) block_size)) ms;
              Ret ^(nil: list byte)
            Rof ^((nil:list byte));
Ret ^(nil: list byte). *)
 
Definition write_last_block lxp ixp inum fms block_off data:=
    fms <- write_first_block lxp ixp inum fms block_off 0 data;
    Ret (fms).

Definition write lxp ixp inum off data fms :=
    let^ (fms, flen) <- BFILE.getlen lxp ixp inum fms;          (* get file length *)
    let len := min (length data) (flen - off) in
    let block_size := valubytes in            (* get block size *)
    let block_off := off / block_size in              (* calculate block offset *)
    let byte_off := off mod block_size in          (* calculate byte offset *)
    let first_write_length := min (block_size - byte_off) len in (*# of bytes that will be read from first block*)
    
    fms <- write_first_block lxp ixp inum fms block_off byte_off (firstn first_write_length data);
    
    let block_off := S block_off in
    let len_remain := (len - first_write_length) in  (* length of remaining part *)
    let data_remain := skipn first_write_length data in
    let num_of_full_blocks := (len_remain / block_size) in (* number of full blocks in length *)
    
   fms <- write_middle_blocks lxp ixp inum fms block_off num_of_full_blocks data_remain;
    
    let off_final := (block_off + num_of_full_blocks) in (* offset of final block *)
    let len_final := (len_remain - num_of_full_blocks * block_size) in (* final remaining length *)
    let data_final := skipn (num_of_full_blocks * block_size) data_remain in
    (*Write last block*)
    fms <- write_last_block lxp ixp inum fms off_final data_final;
  
    Ret (fms).
    
  

(*Same as BFile*)
 Definition getlen lxp ixp inum fms :=
    let '(al, ms) := (BFILE.MSAlloc fms, BFILE.MSLL fms) in
    let^ (ms, n) <- INODE.getlen lxp ixp inum ms;
    Ret ^(BFILE.mk_memstate al ms, n).

  Definition getattrs T lxp ixp inum fms rx : prog T :=
    let '(al, ms) := (BFILE.MSAlloc fms, BFILE.MSLL fms) in
    let^ (ms, n) <- INODE.getattrs lxp ixp inum ms;
    rx ^(BFILE.mk_memstate al ms, n).

  Definition setattrs T lxp ixp inum a fms rx : prog T :=
    let '(al, ms) := (BFILE.MSAlloc fms, BFILE.MSLL fms) in
    ms <- INODE.setattrs lxp ixp inum a ms;
    rx (BFILE.mk_memstate al ms).

  Definition updattr T lxp ixp inum kv fms rx : prog T :=
    let '(al, ms) := (BFILE.MSAlloc fms, BFILE.MSLL fms) in
    ms <- INODE.updattr lxp ixp inum kv ms;
    rx (BFILE.mk_memstate al ms).
    

(* Helper lemmas.*)

Lemma block_content_match: forall F f vs block_off def, 
(F * block_off|-> vs)%pred (list2nmem(BFILE.BFData f))-> 
vs = selN (BFILE.BFData f) block_off def.
Proof.
intros.
unfold valu2list.
eapply ptsto_valid' in H.
unfold list2nmem in H.
erewrite selN_map in H.
simpl in H.
unfold map in H.
symmetry;
apply some_eq. apply H.
eapply selN_map_some_range.
apply H.
Qed.

Lemma pick_from_block: forall F f block_off vs i def def', 
i < valubytes -> (F * block_off |-> vs)%pred (list2nmem (BFILE.BFData f)) ->
selN (valu2list (latest vs)) i def = selN (valu2list (latest (selN (BFILE.BFData f) block_off def'))) i def.
Proof.
intros.
erewrite block_content_match with (f:=f) (vs:=vs) (block_off:= block_off) (def:= def').
reflexivity.
apply H0.
Qed.

Lemma len_f_fy: forall f fy,
ByFData fy =
     firstn (length(ByFData fy))
       (flat_map valuset2bytesets (BFILE.BFData f))->
 length (ByFData fy) <= length (BFILE.BFData f) * valubytes.
Proof.
intros.
rewrite H.
rewrite firstn_length.
rewrite flat_map_len.
apply Min.le_min_r.
Qed.


Lemma addr_id: forall A (l: list A) a def, 
a < length l ->
((diskIs (mem_except (list2nmem l) a)) * a |-> (selN l a def))%pred (list2nmem l).

Proof.
intros.
eapply diskIs_extract.
eapply list2nmem_ptsto_cancel in H.
pred_apply; cancel.
firstorder.
Qed.

Lemma bytefile_unified_byte_len: forall ufy fy, 
bytefile_valid ufy fy -> 
length(ByFData fy) <= length(UByFData ufy).
Proof.
intros.
rewrite H.
rewrite firstn_length.
apply Min.le_min_r.
Qed.

Lemma unified_byte_protobyte_len: forall pfy ufy k,
unified_bytefile_valid pfy ufy ->
Forall (fun sublist : list byteset => length sublist = k) (PByFData pfy) ->
length(UByFData ufy) = length (PByFData pfy) * k.
Proof.
intros.
rewrite H.
apply concat_hom_length with (k:= k).
apply H0.
Qed.

Lemma byte2unifiedbyte: forall ufy fy F a b,
bytefile_valid ufy fy ->
(F * a|-> b)%pred (list2nmem (ByFData fy)) ->
 (F * (arrayN (ptsto (V:= byteset)) (length(ByFData fy)) 
          (skipn (length(ByFData fy)) (UByFData ufy)))
  * a|->b)%pred (list2nmem (UByFData ufy)).
Proof.
unfold bytefile_valid; intros.
pose proof H0.
rewrite H in H0.
apply list2nmem_sel with (def:= byteset0) in H0.
rewrite H0.
rewrite selN_firstn.
apply sep_star_comm.
apply sep_star_assoc.
replace (list2nmem(UByFData ufy))
    with (list2nmem(ByFData fy ++ skipn (length (ByFData fy)) (UByFData ufy))).
apply list2nmem_arrayN_app.
apply sep_star_comm.
rewrite selN_firstn in H0.
rewrite <- H0.
apply H1.
apply list2nmem_inbound in H1.
apply H1.
rewrite H.
rewrite firstn_length.
rewrite Min.min_l. 
rewrite firstn_skipn.
reflexivity.
apply bytefile_unified_byte_len.
apply H.
apply list2nmem_inbound in H1.
apply H1.
Qed.

Lemma unifiedbyte2protobyte: forall pfy ufy a b F k,
unified_bytefile_valid pfy ufy ->
Forall (fun sublist : list byteset => length sublist = k) (PByFData pfy) ->
k > 0 ->
(F * a|->b)%pred (list2nmem (UByFData ufy)) ->
(diskIs (mem_except (list2nmem (PByFData pfy)) (a/k))  * 
(a/k) |-> get_sublist (UByFData ufy) ((a/k) * k) k)%pred (list2nmem (PByFData pfy)).
Proof.
unfold get_sublist, unified_bytefile_valid.
intros.
rewrite H.
rewrite concat_hom_skipn with (k:= k).
replace (k) with (1 * k) by omega.
rewrite concat_hom_firstn.
rewrite firstn1.
rewrite skipn_selN.
simpl.
repeat rewrite <- plus_n_O.
apply addr_id.
apply Nat.div_lt_upper_bound.
unfold not; intros.
rewrite H3 in H1; inversion H1.
rewrite Nat.mul_comm.
rewrite <- unified_byte_protobyte_len with (ufy:= ufy).
apply list2nmem_inbound in H2.
apply H2.
apply H.
apply H0.
simpl;  rewrite <- plus_n_O.
apply forall_skipn.
apply H0.
apply H0.
Qed.

Lemma protobyte2block: forall a b f pfy,
proto_bytefile_valid f pfy ->
(diskIs (mem_except (list2nmem (PByFData pfy)) a) * a|->b)%pred (list2nmem (PByFData pfy)) ->
(diskIs (mem_except (list2nmem (BFILE.BFData f)) a) * a|->(bytesets2valuset b))%pred (list2nmem (BFILE.BFData f)).
Proof.
unfold proto_bytefile_valid; intros.
rewrite H in H0.
pose proof H0.
eapply list2nmem_sel in H0.
erewrite selN_map in H0.
rewrite H0.
rewrite valuset2bytesets2valuset.
apply addr_id.
apply list2nmem_inbound in H1.
rewrite map_length in H1.
apply H1.
apply list2nmem_inbound in H1.
rewrite map_length in H1.
apply H1.
Grab Existential Variables.
apply nil.
apply valuset0.
Qed. 

Lemma bytefile_bfile_eq: forall f pfy ufy fy,
proto_bytefile_valid f pfy -> 
unified_bytefile_valid pfy ufy -> 
bytefile_valid ufy fy ->
ByFData fy = firstn (length (ByFData fy)) (flat_map valuset2bytesets (BFILE.BFData f)).
Proof.
unfold proto_bytefile_valid, 
    unified_bytefile_valid, 
    bytefile_valid.
intros.
destruct_lift H.
rewrite flat_map_concat_map.
rewrite <- H.
rewrite <- H0.
apply H1.
Qed.

Fact inlen_bfile: forall f pfy ufy fy i j Fd data, 
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
j < valubytes -> length data > 0 ->
(Fd ✶ arrayN (ptsto (V:=byteset)) (i * valubytes + j) data)%pred (list2nmem (ByFData fy)) ->
i < length (BFILE.BFData f).
Proof.
intros.
eapply list2nmem_arrayN_bound in H4.
destruct H4.
rewrite H4 in H3.
inversion H3.
rewrite len_f_fy with (f:=f) (fy:=fy) in H4.
apply le2lt_l in H4.
apply lt_weaken_l with (m:= j) in H4.
apply lt_mult_weaken in H4.
apply H4.
apply H3.
eapply bytefile_bfile_eq.
apply H.
apply H0.
apply H1.
Qed.

Fact block_exists: forall f pfy ufy fy i j Fd data,
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
j < valubytes -> length data > 0 ->
(Fd ✶ arrayN (ptsto (V:=byteset)) (i * valubytes + j) data)%pred (list2nmem (ByFData fy)) ->
exists F vs, (F ✶ i |-> vs)%pred (list2nmem (BFILE.BFData f)).
Proof.
intros.
repeat eexists.
eapply unifiedbyte2protobyte with (a:= i * valubytes + j) (k:= valubytes)in H0.
rewrite div_eq in H0.
unfold proto_bytefile_valid in H.
eapply protobyte2block; eauto.
apply H2.
apply Forall_forall; intros.
rewrite H in H5.
apply in_map_iff in H5.
destruct H5.
inversion H5.
rewrite <- H6.
apply valuset2bytesets_len.
omega.
eapply byte2unifiedbyte.
eauto.
pred_apply.
rewrite arrayN_isolate with (i:=0).
rewrite <- plus_n_O .
cancel.
auto.
Grab Existential Variables.
apply byteset0.
Qed.

Fact proto_len: forall f pfy,
proto_bytefile_valid f pfy ->
Forall (fun sublist : list byteset => length sublist = valubytes) (PByFData pfy).
Proof.
intros.
apply Forall_forall; intros.
rewrite H in H0.
apply in_map_iff in H0.
destruct H0.
inversion H0.
rewrite <- H1.
apply valuset2bytesets_len.
Qed.

Fact proto_skip_len: forall f pfy i,
proto_bytefile_valid f pfy ->
Forall (fun sublist : list byteset => length sublist = valubytes) (skipn i (PByFData pfy)).
Proof.
intros.
apply Forall_forall; intros.
apply in_skipn_in in H0.
rewrite H in H0.
rewrite in_map_iff in H0.
repeat destruct H0.
apply valuset2bytesets_len.
Qed.

(* Fact content_match: forall Fd f pfy ufy fy i j data,
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
(Fd ✶ arrayN (ptsto (V:=byteset)) (i * valubytes + j) data)%pred (list2nmem (ByFData fy)) ->
j < valubytes ->
length data > 0 ->
j + length data <= valubytes ->
get_sublist (valu2list (latest (bytesets2valuset
(get_sublist (UByFData ufy) (i * valubytes) valubytes)))) j (length data) = map (@latest byte) data.
 Proof.
 intros.
       
unfold get_sublist.
apply arrayN_list2nmem in H2 as H1'.
rewrite H1 in H1'.
rewrite <- skipn_firstn_comm in H1'.
rewrite firstn_firstn in H1'.
rewrite Min.min_l in H1'.
rewrite skipn_firstn_comm in H1'.
rewrite H1'.
rewrite firstn_length.
rewrite skipn_length.
rewrite Min.min_l.
rewrite <- firstn_map_comm.
rewrite Nat.add_comm.
rewrite <- skipn_skipn with (m:= i * valubytes).
rewrite H0.
rewrite concat_hom_skipn.


replace (firstn valubytes (concat (skipn i (PByFData pfy))))
  with (firstn (1 * valubytes) (concat (skipn i (PByFData pfy)))).
rewrite concat_hom_firstn.
rewrite firstn1.
rewrite skipn_selN.
rewrite <- skipn_map_comm.
rewrite concat_map.
repeat rewrite <- skipn_firstn_comm.
rewrite concat_hom_O with (k:= valubytes).
repeat erewrite selN_map.
rewrite skipn_selN.
rewrite <- plus_n_O.
unfold bytesets2valuset.


Fact latest_l2n: forall A (l: list A) def def',
l <> nil -> latest (list2nelist def l) = selN l 0 def'.
Proof.
intros.
unfold list2nelist.
destruct l.
destruct H; reflexivity.
simpl.
unfold singular.
rewrite pushdlist_app; rewrite app_nil_r.
rewrite rev_involutive.
rewrite <-minus_n_O.
destruct (length l); reflexivity.
Qed.

erewrite latest_l2n.
unfold nelist2list.
Fact b2v_rec_selN: forall i j l def def',
i > 0 -> length l = i -> j < i ->
selN (bytesets2valuset_rec l i) j def = map (selN' j def') l.
simpl.

unfold list2nelist.
simpl.
rewrite valuset2bytesets2valuset.

repeat rewrite skipn_map_comm.
repeat rewrite <- skipn_firstn_comm.
About concat_hom_O.
rewrite concat_hom_O with (k:= valubytes).
erewrite selN_map.
rewrite selN_map with (default':=valuset0).
rewrite skipn_selN.
rewrite <- plus_n_O.
unfold valuset2bytesets.
rewrite maplatest_v2b.
erewrite selN_map.
(selN (BFILE.BFData f) i valuset0).
simpl.
unfold nelist2list.
unfold latest.
remember (snd (selN (BFILE.BFData f) i valuset0)) as s.

rewrite selN_app1.
unfold latest; simpl.
destruct (selN (BFILE.BFData f) i valuset0).

unfold valu2list.
simpl.
unfold bsplit1_dep, bsplit2_dep; simpl.
rewrite skipn_map_comm.
rewrite maplatest_v2b.
rewrite mapfst_valuset2bytesets.
reflexivity.

apply valu2list_len.

rewrite skipn_length.
apply Nat.lt_add_lt_sub_r.
simpl.
eapply inlen_bfile; eauto.

rewrite map_length.
rewrite skipn_length.
apply Nat.lt_add_lt_sub_r.
simpl.
eapply inlen_bfile; eauto.

rewrite Forall_forall; intros.
rewrite in_map_iff in H6.
repeat destruct H6.
rewrite in_map_iff in H7.
repeat destruct H7.
repeat destruct H6.
rewrite map_length.
apply valuset2bytesets_len.
auto.
eapply inlen_bfile; eauto.
eapply proto_len; eauto.

eapply proto_skip_len; eauto.

simpl.
rewrite <- plus_n_O.
reflexivity.

eapply proto_len; eauto.

apply list2nmem_arrayN_bound in H2.
destruct H2.
rewrite H2 in H4; inversion H4.
apply Nat.le_add_le_sub_l.
rewrite bytefile_unified_byte_len in H2.
apply H2.
auto.

apply list2nmem_arrayN_bound in H2.
destruct H2.
rewrite H2 in H4; inversion H4.
apply H2.

apply byteset0.

Grab Existential Variables.
apply nil.
apply valuset0.
Qed. *)



Fact iblocks_file_len_eq: forall F bxp ixp flist ilist frees m inum,
inum < length ilist ->
(F * BFILE.rep bxp ixp flist ilist frees)%pred m ->
length (INODE.IBlocks (selN ilist inum INODE.inode0)) = length (BFILE.BFData (selN flist inum BFILE.bfile0)).
Proof. 
intros.
unfold BFILE.rep in H0.
repeat rewrite sep_star_assoc in H0.
apply sep_star_comm in H0.
repeat rewrite <- sep_star_assoc in H0.

unfold BFILE.file_match in H0.
rewrite listmatch_isolate with (i:=inum) in H0.
sepauto.
rewrite listmatch_length_pimpl in H0.
sepauto.
rewrite listmatch_length_pimpl in H0.
sepauto.
Qed.




Fact fst_l2nel: forall A (l:list A) def,
fst(list2nelist def l) = selN l (length l -1) def.
Proof.
intros.
induction l.
reflexivity.
simpl.
rewrite <- minus_n_O.
unfold singular; rewrite pushdlist_app.
simpl.
reflexivity.
Qed.




Fact nel2l_O: forall A (l: nelist A) def,
selN (nelist2list l) 0 def = latest l.
Proof.
intros.
induction l.
unfold nelist2list, latest.
simpl.
destruct b; reflexivity.
Qed.



(*Specs*)








(* Theorem read_last_block_ok: forall lxp bxp ixp inum fms block_off read_length,
 {< F Fm Fi Fd m0 m flist ilist frees f fy data,
    PRE:hm
          let file_length := (# (INODE.ABytes (ByFAttr fy))) in
          let block_size := valubytes in
           rep lxp bxp ixp flist ilist frees inum  F Fm Fi fms m0 m hm f fy  *
           [[[ (ByFData fy) ::: (Fd * (arrayN (ptsto (V:= byteset)) (block_off * block_size) data)) ]]] *
           [[ 0 < read_length]] * 
           [[ length data = read_length ]] *
           [[ read_length < block_size]]
    POST:hm' RET:^(fms', r)
          LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms') hm' *
          [[ r = map (@latest byte) data ]] *
          [[BFILE.MSAlloc fms = BFILE.MSAlloc fms' ]]
    CRASH:hm'  exists (fms':BFILE.memstate),
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms') hm'
    >} read_last_block lxp ixp inum fms block_off read_length.
Proof.
unfold read_last_block, rep.
step.

eapply list2nmem_arrayN_bound in H8.
destruct H8.
rewrite H in H7.
inversion H7.
rewrite len_f_fy with (f:=f) (fy:=fy) in H.
apply le2lt_l in H.
replace (block_off * valubytes) with (block_off * valubytes + 0) in H by omega.
apply lt_weaken_l with (m:= 0) in H.
apply lt_mult_weaken in H.
apply H.
apply H7.
eapply bytefile_bfile_eq.
eauto.
eauto.
eauto.

eapply protobyte2block; eauto.
eapply unifiedbyte2protobyte with (a:= block_off * valubytes + 0) (k:= valubytes) in H11; try omega.
rewrite div_eq in H11; try omega.
apply H11.

eapply proto_len; eauto.
eapply byte2unifiedbyte; eauto.
pred_apply.
rewrite arrayN_isolate with (i:=0).
rewrite <- plus_n_O .
cancel.
auto.

step.

eapply content_match; eauto.
rewrite <- plus_n_O.
eauto.
omega.
omega.

Grab Existential Variables.
apply byteset0.
Qed.

 *)

Theorem read_first_block_ok: forall lxp bxp ixp inum fms block_off byte_off read_length,
 {< F Fm Fi Fd m0 m flist ilist frees f fy (data: list byteset),
    PRE:hm
          let file_length := (# (INODE.ABytes (ByFAttr fy))) in
          let block_size := valubytes in
           rep lxp bxp ixp flist ilist frees inum  F Fm Fi fms m0 m hm f fy  *
           [[[ (ByFData fy) ::: (Fd * (arrayN (ptsto (V:= byteset)) (block_off * block_size + byte_off) data)) ]]] *
           [[ 0 < read_length]] * 
           [[ length data = read_length ]] *
           [[ byte_off + read_length <= block_size]]
    POST:hm' RET:^(fms', r)
          LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms') hm' *
          [[ r = (map (@latest byte) data) ]] *
          [[BFILE.MSAlloc fms = BFILE.MSAlloc fms' ]]
    CRASH:hm'  exists (fms':BFILE.memstate),
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms') hm'
    >} read_first_block lxp ixp inum fms block_off byte_off read_length.
Proof.
unfold read_first_block, rep.
step.

eapply inlen_bfile; eauto.
omega.

eapply protobyte2block; eauto.
eapply unifiedbyte2protobyte with (a:= block_off * valubytes + byte_off) (k:= valubytes) in H11; try omega.
rewrite div_eq in H11; try omega.
apply H11.

eapply proto_len; eauto.
eapply byte2unifiedbyte; eauto.
pred_apply.
rewrite arrayN_isolate with (i:=0).
rewrite <- plus_n_O .
cancel.
auto.

step.

apply arrayN_list2nmem in H8 as H1'.
rewrite H10 in H1'.
rewrite <- skipn_firstn_comm in H1'.
rewrite firstn_firstn in H1'.
rewrite Min.min_l in H1'.
rewrite skipn_firstn_comm in H1'.
rewrite H1'.
unfold get_sublist.
rewrite firstn_length.
rewrite skipn_length.
rewrite Min.min_l.
rewrite <- firstn_map_comm.
rewrite Nat.add_comm.
rewrite <- skipn_skipn with (m:= block_off * valubytes).
rewrite H11.
rewrite concat_hom_skipn.


replace (firstn valubytes (concat (skipn block_off (PByFData pfy))))
  with (firstn (1 * valubytes) (concat (skipn block_off (PByFData pfy)))).
rewrite concat_hom_firstn.
rewrite firstn1.
rewrite skipn_selN.
rewrite <- skipn_map_comm.
rewrite concat_map.
repeat rewrite <- skipn_firstn_comm.
rewrite concat_hom_O with (k:= valubytes).
rewrite selN_map with (default':=nil).
rewrite skipn_selN.
rewrite <- plus_n_O.

rewrite H12.
rewrite selN_map with (default':= valuset0).
rewrite valuset2bytesets2valuset.



eapply protobyte2block with (a:= block_off) in H12.
eapply list2nmem_sel in H12.
rewrite <- H12.

rewrite bytesets2valuset2bytesets.

unfold bytesets2valuset.
rewrite fst_l2nel.
rewrite nel2l_O.
unfold nelist2list.
simpl.
rewrite app_length.
simpl.
rewrite map_app.
simpl.

Fact b2v_rec_length: forall i l,
i <= length l ->
length (bytesets2valuset_rec l i) = i.
Proof.
induction i; intros.
reflexivity.
destruct l.
inversion H.
simpl.
rewrite IHi.
reflexivity.
destruct l.
simpl in H.



Fact b2v_rec_expand: forall l i,
i > 0 -> l<> nil ->
bytesets2valuset_rec l i =  (list2valu (map (selN' 0 byte0) l) )::(bytesets2valuset_rec (map (skipn 1) l) (i-1)).
Proof.
intros.
induction i.
inversion H.

simpl.
rewrite <- minus_n_O.
destruct l.
destruct H0; reflexivity.
reflexivity.
Qed.

simpl.
rewrite map_length.
omega.
simpl in *.
rewrite map_length; omega.
Qed.

rewrite b2v_rec_length.
Search plus minus.
replace (1 - 1) with 0 by omega.
simpl.



reflexivity.
simpl.
destruct a.
simpl.



destruct (?b).
unfold nelist2list.
rewrite map_app.
simpl.
rewrite maplatest_v2b.


unfold bytesets2valuset.
simpl.



simpl.
rewrite app_length,
simpl.
unfold selN. 



remember (selN (BFILE.BFData f) block_off valuset0) as s.
destruct s.
pose proof H10.
eapply byte2unifiedbyte with (a:= block_off * valubytes + 0) in H10.
eapply unifiedbyte2protobyte with (k:= valubytes)(pfy:=pfy) in H10.
rewrite div_eq in H10.
eapply list2nmem_sel in H10.
rewrite <- Heqs in H10.
apply length_zero_iff_nil in H10.
unfold get_sublist in H10.
rewrite firstn_length in H10.
rewrite skipn_length in H10.


Fact min_O: forall n m,
Init.Nat.min n m = 0 -> n = 0 \/ m = 0.
intros.
destruct n.
left; reflexivity.
right.
destruct m.
reflexivity.
inversion H.
Qed.



apply min_O in H10.
destruct H10.
rewrite valubytes_is in H6; inversion H6.
Search minus 0.
apply list2nmem_arrayN_bound in H8.
destruct H8.
rewrite H8 in H7; inversion H7.
rewrite H4 in H8.
rewrite firstn_length in H8.
apply Min.min_glb_r in H8.
About le2lt_l.
apply le2lt_l in H8.
apply lt_weaken_l in H8.
Search minus 0.
apply Nat.sub_gt in H8.
apply H8 in H6; inversion H6.
omega.
rewrite valubytes_is; omega.
auto.
eapply proto_len; eauto.
rewrite valubytes_is; omega.
rewrite <- plus_n_O.
eapply list2nmem_ptsto_cancel.
apply list2nmem_arrayN_bound in H8.
destruct H8.
rewrite H6 in H7; inversion H7.
apply le2lt_l in H6.
apply lt_weaken_l in H6.
apply H6.
omega.

simpl.
unfold bytesets2valuset.
simpl.

unfold valu2list.
rewrite b2v_rec_selN.

rewrite H4.
Search list2nmem ptsto.
rewrite H11.
Search list2nmem lt ptsto.
eapply byte2unifiedbyte in H4.
apply Nat.le_add_le_sub_l.
Search le plus.
rewrite <- Heqs in H4.
simpl.
unfold valu2list.
simpl.
unfold bytesets2valuset.
unfold bytesets2valuset_rec.

simpl.
unfold list2nelist; simpl.


Fact latest_l2n: forall A (l: list A) def def',
l <> nil -> latest (list2nelist def l) = selN l 0 def'.
Proof.
intros.
unfold list2nelist.
destruct l.
destruct H; reflexivity.
simpl.
unfold singular.
rewrite pushdlist_app; rewrite app_nil_r.
rewrite rev_involutive.
rewrite <-minus_n_O.
destruct (length l); reflexivity.
Qed.


eapply content_match; eauto.
omega.
Grab Existential Variables.
apply byteset0. 
Qed.


Theorem read_middle_blocks_ok: forall lxp bxp ixp inum fms block_off num_of_full_blocks,
 {< F Fm Fi Fd m0 m flist ilist frees f fy (data: list byteset),
    PRE:hm
          let file_length := (# (INODE.ABytes (ByFAttr fy))) in
          let block_size := valubytes in
           rep lxp bxp ixp flist ilist frees inum  F Fm Fi fms m0 m hm f fy *
           [[[ (ByFData fy) ::: (Fd * (arrayN (ptsto (V:=byteset)) (block_off * block_size) data))]]] *
           [[ num_of_full_blocks > 0 ]] *
           [[ length data = mult num_of_full_blocks block_size ]]
    POST:hm' RET:^(fms', r)
          LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms') hm' *
          [[ r = (map (@latest byte) data)]] *
          [[BFILE.MSAlloc fms = BFILE.MSAlloc fms' ]]
    CRASH:hm'  exists (fms':BFILE.memstate),
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms') hm'
    >} read_middle_blocks lxp ixp inum fms block_off num_of_full_blocks.
Proof.
unfold read_middle_blocks, rep; step.
rewrite valubytes_is; reflexivity.
prestep.
norm.
unfold stars.
simpl.
rewrite LOG.rep_hashmap_subset by eauto.
cancel.
intuition.
eapply pimpl_pre2; intros.
repeat ( apply sep_star_lift_l; intros ).
unfold pimpl, lift; intros.
eapply pimpl_ok2. repeat monad_simpl.
Focus 2. intros.
apply pimpl_refl.
Admitted.

Theorem read_ok : forall lxp bxp ixp inum off len fms,
    {< F Fm Fi Fd m0 m flist ilist frees f fy data,
    PRE:hm
        let file_length := (# (INODE.ABytes (ByFAttr fy))) in
        let block_size := valubytes in
           rep lxp bxp ixp flist ilist frees inum  F Fm Fi fms m0 m hm f fy  *
           [[[ (ByFData fy) ::: (Fd * (arrayN (ptsto (V:= byteset)) off data)) ]]] *
           [[ length data = len ]]
    POST:hm' RET:^(fms', r)
          LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms') hm' *
          [[ r = map (@latest byte) data]] *
          [[BFILE.MSAlloc fms = BFILE.MSAlloc fms' ]]
    CRASH:hm'  exists (fms':BFILE.memstate),
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms') hm'
    >} read lxp ixp inum off len fms.
Proof.
unfold rep, read.
unfold If_.
step.
destruct (lt_dec off a0);
destruct(lt_dec 0 ((Init.Nat.min (length data) (a0 - off) -
         Init.Nat.min (valubytes - off mod valubytes) 
         (Init.Nat.min (length data) (a0 - off))) / valubytes));
destruct (lt_dec 0 (Init.Nat.min (length data) (a0 - off) -
          Init.Nat.min (valubytes - off mod valubytes)
          (Init.Nat.min (length data) (a0 - off)) -
          (Init.Nat.min (length data) (a0 - off) -
          Init.Nat.min (valubytes - off mod valubytes)
          (Init.Nat.min (length data) (a0 - off))) / valubytes * valubytes)).
          constructor.
destruct_lift H.
Admitted.

Fixpoint updN_list A (l: list A) off (l1: list A): list A :=
match l1 with
| nil => l
| h::t => updN_list (updN l off h) (S off) t
end.

Theorem write_first_block_ok : forall lxp bxp ixp inum block_off byte_off data fms,
    {< F Fm Fi Fd m0 m flist ilist frees f fy old_data,
    PRE:hm
           rep lxp bxp ixp flist ilist frees inum  F Fm Fi fms m0 m hm f fy  *
           [[[ (ByFData fy) ::: (Fd * arrayN (ptsto (V:=byteset)) (block_off * valubytes + byte_off) old_data)]]] *
           [[ length old_data = length data]] *
           [[ length data > 0 ]] *
           [[ byte_off + length data <= valubytes ]] 
    POST:hm' RET:fms'  exists m' flist' f' fy',
           rep lxp bxp ixp flist' ilist frees inum  F Fm Fi fms' m0 m' hm' f' fy' *
           [[[ (ByFData fy') ::: (Fd * arrayN (ptsto (V:=byteset)) (block_off * valubytes + byte_off) 
            (map (@singular byte) data))]]] *
           [[ fy' = mk_bytefile (updN_list (ByFData fy) (block_off * valubytes + byte_off) 
           (map (@singular byte) data)) (ByFAttr fy) ]] *
           [[ BFILE.MSAlloc fms = BFILE.MSAlloc fms' ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} write_first_block lxp ixp inum fms block_off byte_off data.

Proof.
unfold write_first_block, rep.
step.

eapply inlen_bfile; try eauto; try omega.

eapply protobyte2block; eauto.
eapply unifiedbyte2protobyte with (a:= block_off * valubytes + byte_off) (k:= valubytes) in H11; try omega.
rewrite div_eq in H11; try omega.
apply H11.

eapply proto_len; eauto.

eapply byte2unifiedbyte; eauto.
pred_apply.
rewrite arrayN_isolate with (i:=0).
rewrite <- plus_n_O .
cancel.
omega.

step.

erewrite iblocks_file_len_eq.

eapply inlen_bfile; eauto.
eapply list2nmem_sel in H13.
rewrite <- H13.
auto.
rewrite valubytes_is in *; omega.
omega.

Show Existentials.
Existential  9:= ilist.
auto.
apply list2nmem_inbound in H13.
unfold BFILE.rep in H0.
replace (length ilist) with (length flist).
apply H13.
rewrite listmatch_length_pimpl in H0.
destruct_lift H0.
apply H21.
apply H0.
unfold BFILE.rep.
cancel.
apply addr_id.

apply list2nmem_inbound in H13.
unfold BFILE.rep in H0.
replace (length ilist) with (length flist).
apply H13.
rewrite listmatch_length_pimpl in H0.
destruct_lift H0.
apply H21.

step.

pose proof H0 as H0'.
unfold BFILE.rep in H0.
destruct_lift H0.
unfold BFILE.file_match in H0.
rewrite listmatch_isolate with (i:= inum) in H0.
destruct_lift H0.
unfold listmatch in H0.
destruct_lift H0.

remember((((Fm ✶ BALLOC.rep bxp_1 frees_1) ✶ BALLOC.rep bxp_2 frees_2)
        ✶ INODE.rep bxp_1 ixp ilist)
       ✶ listpred
           (pprd
              (fun (f : BFILE.bfile) (i : INODE.inode) =>
               (⟦⟦ length (BFILE.BFData f) =
                   length (map (wordToNat (sz:=addrlen)) (INODE.IBlocks i)) ⟧⟧
                ✶ listpred (pprd (fun (v : BFILE.datatype) (a : addr) => a |-> v))
                    (combine (BFILE.BFData f)
                       (map (wordToNat (sz:=addrlen)) (INODE.IBlocks i))))
               ✶ ⟦⟦ BFILE.BFAttr f = INODE.IAttr i ⟧⟧))
           (combine (removeN flist inum) (removeN ilist inum)))%pred as F'.
           
rewrite listpred_isolate with (i:= block_off) in H0.

unfold pprd in H0.
unfold prod_curry in H0.
apply sep_star_assoc in H0.
erewrite selN_combine in H0.
eapply list2nmem_sel with (F:= (F'
       ✶ listpred (fun p : BFILE.datatype * addr => let (x, y) := p in y |-> x)
           (removeN
              (combine (BFILE.BFData flist ⟦ inum ⟧)
                 (map (wordToNat (sz:=addrlen)) (INODE.IBlocks ilist ⟦ inum ⟧)))
              block_off))%pred) in H0.
              
              erewrite selN_map in H0.
rewrite H14 in H0.
eapply list2nmem_sel in H13.
rewrite <- H13 in H0.
3: apply H20.
Focus 2.
eapply list2nmem_sel in H13 as H13'.
erewrite iblocks_file_len_eq with (flist:= flist).
eapply inlen_bfile; eauto; try omega.
rewrite <- H13'; eauto.


apply list2nmem_inbound in H13.
unfold BFILE.rep in H0'.
replace (length ilist) with (length flist).
apply H13.
rewrite listmatch_length_pimpl in H0'.
destruct_lift H0'.
eauto.
eauto.

Focus 2.
rewrite combine_length.
rewrite map_length.
eapply list2nmem_sel in H13 as H13'.
erewrite iblocks_file_len_eq with (flist:=flist).
repeat rewrite <- H13'.
rewrite Nat.min_id.
eapply inlen_bfile; eauto; try omega.
apply list2nmem_inbound in H13.
unfold BFILE.rep in H0'.
replace (length ilist) with (length flist).
apply H13.
rewrite listmatch_length_pimpl in H0'.
destruct_lift H0'.
eauto.
eauto.

Focus 2.
apply list2nmem_inbound in H13.
apply H13.

Focus 2.
apply list2nmem_inbound in H13.
unfold BFILE.rep in H0'.
replace (length ilist) with (length flist).
apply H13.
rewrite listmatch_length_pimpl in H0'.
destruct_lift H0'.
eauto.
eauto.

Focus 2.
unfold pimpl; intros.
unfold BFILE.rep in H14.
rewrite listmatch_isolate with (i:= inum) in H14.
unfold BFILE.file_match in H14.
destruct_lift H14.
apply sep_star_comm in H14.
rewrite listmatch_isolate with (i:= block_off) in H14.
erewrite selN_map in H14.
apply sep_star_comm in H14.
apply sep_star_assoc in H14.
apply sep_star_comm.
apply mem_except_ptsto.
apply sep_star_comm in H14.
apply ptsto_valid in H14.
replace (?anon, ?anon0) 
  with (selN (BFILE.BFData (selN flist inum BFILE.bfile0)) block_off valuset0).
apply H14.
apply injective_projections; reflexivity.
apply sep_star_comm in H14.
apply ptsto_mem_except in H14.
apply H14.

erewrite iblocks_file_len_eq with (flist:= flist).
eapply list2nmem_sel in H13.
rewrite <- H13.
eapply inlen_bfile; eauto; try omega.

apply list2nmem_inbound in H13.
unfold BFILE.rep in H0.
replace (length ilist) with (length flist).
apply H13.
rewrite listmatch_length_pimpl in H0.
destruct_lift H0.
eauto.
eauto.

eapply list2nmem_sel in H13.
rewrite <- H13.
eapply inlen_bfile; eauto; try omega.

rewrite map_length.
erewrite iblocks_file_len_eq with (flist:= flist).
eapply list2nmem_sel in H13.
rewrite <- H13.
eapply inlen_bfile; eauto; try omega.

apply list2nmem_inbound in H13.
unfold BFILE.rep in H0.
replace (length ilist) with (length flist).
apply H13.
rewrite listmatch_length_pimpl in H0.
destruct_lift H0.
eauto.
eauto.

apply list2nmem_inbound in H13.
apply H13.


apply list2nmem_inbound in H13.
unfold BFILE.rep in H0.
replace (length ilist) with (length flist).
apply H13.
rewrite listmatch_length_pimpl in H0.
destruct_lift H0.
eauto.

Focus 2.
step.
unfold pimpl; intros.
eauto.
unfold BFILE.rep in H0.
sepauto.
eapply pimpl_pre3 in H2.
destruct H2.
eauto.
repeat destruct H2.
repeat eexists.
eauto.
destruct_lift H14.
rewrite H20.

Admitted.



  Ltac assignms :=
    match goal with
    [ fms : BFILE.memstate |- LOG.rep _ _ _ ?ms _ =p=> LOG.rep _ _ _ (BFILE.MSLL ?e) _ ] =>
      is_evar e; eassign (BFILE.mk_memstate (BFILE.MSAlloc fms) ms); simpl; eauto
    end.

  Local Hint Extern 1 (LOG.rep _ _ _ ?ms _ =p=> LOG.rep _ _ _ (BFILE.MSLL ?e) _) => assignms.
    
    Theorem getlen_ok : forall lxp bxps ixp inum ms,
    {< F Fm Fi m0 m f flist ilist frees,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms) hm *
           [[[ m ::: (Fm * BFILE.rep bxps ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]]
    POST:hm' RET:^(ms',r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms') hm' *
           [[ r = length (BFILE.BFData f) /\ BFILE.MSAlloc ms = BFILE.MSAlloc ms' ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms') hm'
    >} getlen lxp ixp inum ms.
  Proof.
    unfold getlen, BFILE.rep.
    safestep.
    sepauto.

    safestep.
    extract; seprewrite; subst.
    setoid_rewrite listmatch_length_pimpl in H at 2.
    destruct_lift H; eauto.
    simplen.

    cancel.
    eauto.
  Qed.


  Theorem getattrs_ok : forall lxp bxp ixp inum ms,
    {< F Fm Fi m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms) hm *
           [[[ m ::: (Fm * BFILE.rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]]
    POST:hm' RET:^(ms',r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms') hm' *
           [[ r = BFILE.BFAttr f /\ BFILE.MSAlloc ms = BFILE.MSAlloc ms' ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms') hm'
    >} getattrs lxp ixp inum ms.
  Proof.
    unfold getattrs, BFILE.rep.
    safestep.
    sepauto.

    safestep.
    extract; seprewrite.
    subst; eauto.

    cancel.
    eauto.
  Qed.



  Theorem setattrs_ok : forall lxp bxps ixp inum a ms,
    {< F Fm Fi m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms) hm *
           [[[ m ::: (Fm * BFILE.rep bxps ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]]
    POST:hm' RET:ms'  exists m' flist' f' ilist',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (BFILE.MSLL ms') hm' *
           [[[ m' ::: (Fm * BFILE.rep bxps ixp flist' ilist' frees) ]]] *
           [[[ flist' ::: (Fi * inum |-> f') ]]] *
           [[ f' = BFILE.mk_bfile (BFILE.BFData f) a ]] *
           [[ BFILE.MSAlloc ms = BFILE.MSAlloc ms' /\
              let free := BFILE.pick_balloc frees (BFILE.MSAlloc ms') in
              BFILE.ilist_safe ilist free ilist' free ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} setattrs lxp ixp inum a ms.
  Proof.
    unfold setattrs, BFILE.rep.
    safestep.
    sepauto.

    safestep.
    repeat extract. seprewrite.
    2: sepauto.
    2: eauto.
    eapply listmatch_updN_selN; try omega.
    unfold BFILE.file_match; cancel.

    denote (list2nmem m') as Hm'.
    rewrite listmatch_length_pimpl in Hm'; destruct_lift Hm'.
    denote (list2nmem ilist') as Hilist'.
    assert (inum < length ilist) by simplen'.
    apply arrayN_except_upd in Hilist'; eauto.
    apply list2nmem_array_eq in Hilist'; subst.
    unfold BFILE.ilist_safe; intuition. left.
    destruct (addr_eq_dec inum inum0); subst.
    - unfold BFILE.block_belong_to_file in *; intuition.
      all: erewrite selN_updN_eq in * by eauto; simpl; eauto.
    - unfold BFILE.block_belong_to_file in *; intuition.
      all: erewrite selN_updN_ne in * by eauto; simpl; eauto.
  Qed.


  Theorem updattr_ok : forall lxp bxps ixp inum kv ms,
    {< F Fm Fi m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms) hm *
           [[[ m ::: (Fm * BFILE.rep bxps ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]]
    POST:hm' RET:ms'  exists m' flist' ilist' f',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (BFILE.MSLL ms') hm' *
           [[[ m' ::: (Fm * BFILE.rep bxps ixp flist' ilist' frees) ]]] *
           [[[ flist' ::: (Fi * inum |-> f') ]]] *
           [[ f' = BFILE.mk_bfile (BFILE.BFData f) (INODE.iattr_upd (BFILE.BFAttr f) kv) ]] *
           [[ BFILE.MSAlloc ms = BFILE.MSAlloc ms' /\
              let free := BFILE.pick_balloc frees (BFILE.MSAlloc ms') in
              BFILE.ilist_safe ilist free ilist' free ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} updattr lxp ixp inum kv ms.
  Proof.
    unfold updattr, BFILE.rep.
    step.
    sepauto.

    safestep.
    repeat extract. seprewrite.
    2: sepauto.
    2: eauto.
    eapply listmatch_updN_selN; try omega.
    unfold BFILE.file_match; cancel.

    denote (list2nmem m') as Hm'.
    rewrite listmatch_length_pimpl in Hm'; destruct_lift Hm'.
    denote (list2nmem ilist') as Hilist'.
    assert (inum < length ilist) by simplen'.
    apply arrayN_except_upd in Hilist'; eauto.
    apply list2nmem_array_eq in Hilist'; subst.
    unfold BFILE.ilist_safe; intuition. left.
    destruct (addr_eq_dec inum inum0); subst.
    - unfold BFILE.block_belong_to_file in *; intuition.
      all: erewrite selN_updN_eq in * by eauto; simpl; eauto.
    - unfold BFILE.block_belong_to_file in *; intuition.
      all: erewrite selN_updN_ne in * by eauto; simpl; eauto.
  Qed.
    
    
    
    
          
(*From BFile

  Definition datasync T lxp ixp inum fms rx : prog T :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, bns) <- INODE.getallbnum lxp ixp inum ms;
    ms <- LOG.dsync_vecs lxp (map (@wordToNat _) bns) ms;
    rx (mk_memstate al ms).

  Definition sync T lxp (ixp : INODE.IRecSig.xparams) fms rx : prog T :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    ms <- LOG.sync lxp ms;
    rx (mk_memstate (negb al) ms).

  Definition pick_balloc A (a : A * A) (flag : bool) :=
    if flag then fst a else snd a.

  Definition grow T lxp bxps ixp inum v fms rx : prog T :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, len) <- INODE.getlen lxp ixp inum ms;
    If (lt_dec len INODE.NBlocks) {
      let^ (ms, r) <- BALLOC.alloc lxp (pick_balloc bxps al) ms;
      match r with
      | None => rx ^(mk_memstate al ms, false)
      | Some bn =>
           let^ (ms, succ) <- INODE.grow lxp (pick_balloc bxps al) ixp inum bn ms;
           If (bool_dec succ true) {
              ms <- LOG.write lxp bn v ms;
              rx ^(mk_memstate al ms, true)
           } else {
             rx ^(mk_memstate al ms, false)
           }
      end
    } else {
      rx ^(mk_memstate al ms, false)
    }.

  Definition shrink T lxp bxps ixp inum nr fms rx : prog T :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, bns) <- INODE.getallbnum lxp ixp inum ms;
    let l := map (@wordToNat _) (skipn ((length bns) - nr) bns) in
    ms <- BALLOC.freevec lxp (pick_balloc bxps (negb al)) l ms;
    ms <- INODE.shrink lxp (pick_balloc bxps (negb al)) ixp inum nr ms;
    rx (mk_memstate al ms).
End*)

End ABYTEFILE.