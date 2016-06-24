Require Import Arith.
Require Import Word.
Require Import Omega.
Require Import List ListUtils.
Require Import FunctionalExtensionality.
Require Import NArith.
Require Import AsyncDisk.
Require Import Bytes.
Require Import NEList.

Notation "'byteset'" := (nelist byte).

Definition valu2bytes (v : valu) : bytes (1 + (valubytes - 1)).
  refine (@word2bytes valulen (1 + (valubytes - 1)) _ v).
  rewrite valulen_is. rewrite valubytes_is. reflexivity.
Defined.

Definition byteset0 := singular byte0.
Definition valu0 := bytes2valu  (natToWord (valubytes*8) 0).
Definition valuset0 := singular valu0.

(* make this right padded *)
Definition bytes2valubytes {sz} (b: bytes sz) : bytes valubytes :=
(word2bytes valubytes eq_refl (natToWord (valubytes*8)(wordToNat b))).

Definition list2valu l: valu :=
bytes2valu (bytes2valubytes (bcombine_list l)).

Definition valu2list v : list byte :=
bsplit_list (valu2bytes v).

Fixpoint make_all_list {A: Type} (l: list A): list (list A):=
match l with
| nil => nil
| h::t => (cons h nil)::(make_all_list t)
end.

Fixpoint maxlist l: nat :=
match l with
| nil => 0
| h::t => max h (maxlist t)
end.

Definition selN' {A: Type} i def (l: list A): A :=
selN l i def.


Fixpoint valuset2bytesets_rec (vs: list (list byte)) i : list byteset :=
match i with
| O => nil
| S i' => match vs with
    | nil => nil
    | _ =>  (list2nelist byte0 (map (selN' 0 byte0) vs))::(valuset2bytesets_rec (map (skipn 1) vs) i')
    end
end.

Definition valuset2bytesets (vs: valuset): list byteset :=
valuset2bytesets_rec (map valu2list (nelist2list vs)) valubytes.

Fixpoint bytesets2valuset_rec (bs: list (list byte) ) i: list valu :=
match i with
| O => nil
| S i' => match bs with
          | nil => nil
          | _ =>  ( list2valu (map (selN' 0 byte0) bs) )::(bytesets2valuset_rec (map (skipn 1) bs) i')
          end
end.

Definition bytesets2valuset (bs: list byteset) : valuset :=
list2nelist valu0 (bytesets2valuset_rec (map (@nelist2list byte) bs) (length(nelist2list(selN bs 0 byteset0)))).

Definition get_sublist {A:Type}(l: list A) (off len: nat) : list A :=
firstn len (skipn off l).
  
(* Lemmas *)

Lemma make_all_list_len: forall (A:Type) (l: list A),
 length(make_all_list l) = length l.
Proof.
induction l.
reflexivity.
simpl; rewrite IHl; reflexivity.
Qed.

Lemma valu2list_len : forall v,
 length(valu2list v) = valubytes.
Proof.
intros.
unfold valu2list.
rewrite bsplit_list_len.
rewrite valubytes_is.
reflexivity.
Qed.

(* Lemma maxlist_len: forall l, 
l <> nil -> 
maxlist (map (fun x : valu => length (valu2list x)) l) = valubytes.
Proof.
induction l; intros.
destruct H; reflexivity.
simpl.
rewrite valu2list_len.
destruct l.
simpl.
apply Nat.max_0_r.
rewrite IHl.
apply Nat.max_id.
unfold not.
intros; inversion H0.
Qed. *)


Lemma valuset2bytesets_rec_expand: forall l i a,
   i > 0 ->
  valuset2bytesets_rec (a::l) i = 
  (list2nelist byte0 (map (selN' 0 byte0) (a::l))) :: (valuset2bytesets_rec (map (skipn 1) (a::l)) (i-1)).
Proof.
destruct l; intros; simpl.
destruct a.
simpl.
destruct i.
inversion H.
simpl.
rewrite <- minus_n_O; reflexivity.
simpl.
destruct i.
inversion H.
simpl.
rewrite <- minus_n_O; reflexivity.
simpl.
destruct i.
inversion H.
simpl.
repeat rewrite <- minus_n_O.
reflexivity.
Qed.

Lemma valuset2bytesets_rec_len: forall i l,  
l <> nil -> length(valuset2bytesets_rec l i) = i.
Proof.
induction i.
reflexivity.
destruct l.
intros.
destruct H; reflexivity.
intros.
rewrite valuset2bytesets_rec_expand.
replace (S i - 1) with i by omega.
simpl.
rewrite IHi.
reflexivity.
unfold not; intros; inversion H0.
omega.
Qed.

Lemma valuset2bytesets_len: forall vs, 
length(valuset2bytesets vs) = valubytes.
Proof.
intros.
unfold valuset2bytesets.
apply valuset2bytesets_rec_len.
unfold nelist2list.
rewrite map_app.
unfold not; intros.
apply length_zero_iff_nil in H.
rewrite app_length in H.
simpl in H.
destruct (length (map valu2list (snd vs))); 
inversion H.
Qed.

(* helper le-lt lemmas. *)
Lemma le_trans: forall n m k, n <= m -> m <= k -> n <= k.
Proof. intros. omega. Qed.

Lemma le_weaken_l: forall n m k, n + m <= k -> n <= k.
Proof. intros. omega. Qed.

Lemma le_weaken_r: forall n m k, n + m <= k -> m <= k.
Proof. intros. omega. Qed.

Lemma lt_weaken_l: forall n m k, n + m < k -> n < k.
Proof. intros. omega. Qed.

Lemma lt_weaken_r: forall n m k, n + m < k -> m < k.
Proof. intros. omega. Qed.

Lemma le2lt_l: forall n m k, n + m <= k -> m > 0 -> n < k.
Proof. intros. omega. Qed.

Lemma le2lt_r: forall n m k, n + m <= k -> n > 0 -> m < k.
Proof. intros. omega. Qed.

Lemma mult_ne_O_l: forall n m p, p * n < p * m -> p > 0.
Proof. 
induction p; intros.
repeat rewrite <- mult_n_O in H; inversion H.
omega.
Qed.

Lemma mult_ne_O_r: forall n m p, n * p < m * p -> p > 0.
Proof. 
induction p; intros.
repeat rewrite <- mult_n_O in H; inversion H.
omega.
Qed.

Lemma plus_lt_compat_rev: forall n m p, p + n < p + m -> n < m.
Proof. intros. omega. Qed.

Lemma lt_mult_weaken: forall p n m, n * p < m * p  -> n < m.
Proof.
assert(A: forall x, 0 * x = 0). intros. omega.
induction n. intros.
destruct m.
rewrite A in H; inversion H.
omega. intros.
destruct m.
rewrite A in H; inversion H.
apply lt_n_S.
apply IHn.
simpl in H.
apply plus_lt_compat_rev in H.
apply H.
Qed.

Lemma some_eq: forall A (x y: A), Some x = Some y <-> x = y.
Proof.
split; intros.
inversion H; reflexivity.
rewrite H; reflexivity.
Qed.

 (*
Lemma concat_hom_selN: forall A (lists: list(list A)) i n k def, 
Forall (fun sublist => length sublist = k) lists ->
i < k ->
selN (concat lists) (n * k + i) def = selN (selN lists n nil) i def.
Proof.
induction lists.
reflexivity.
intros.
rewrite Forall_forall in H.
destruct n.
simpl.
apply selN_app1.
destruct H with (x:= a).
apply in_eq.
apply H0.
destruct H with (x:=a).
apply in_eq.
simpl.
rewrite selN_app2.
replace (length a + n * length a + i - length a) with (n * length a + i).
apply IHlists.
rewrite Forall_forall.
intros.
eapply in_cons in H1.
apply H in H1.
apply H1.
apply H0.
remember (n * length a + i) as x.
replace (length a + n * length a + i - length a) with (length a + x - length a).
omega.
rewrite Heqx.
omega.
unfold ge.
remember (n * length a + i) as x.
replace (length a + n * length a + i) with (length a + x).
apply le_plus_l.
omega.
Qed. *)


 
Lemma latest_l2nel: forall A (l:list A) def, 
  latest(list2nelist def l) =  selN l 0 def.
Proof.
induction l; intros.
reflexivity.
simpl.
unfold singular.
rewrite pushdlist_app.
rewrite <- minus_n_O.
destruct (length l).
reflexivity.
simpl.
rewrite rev_unit.
rewrite rev_involutive.
rewrite app_nil_r.
unfold latest.
reflexivity.
Qed.

Lemma selN_make_all_list: forall A (l: list A) i def,
 i < length l ->
  selN (make_all_list l) i nil = (selN l i def)::nil.
Proof.
induction l.
intros.
inversion H.
intros.
destruct i.
reflexivity.
simpl.
apply IHl.
simpl in H.
omega.
Qed.

Lemma flat_map_len: forall vs, length(flat_map valuset2bytesets vs) = length(vs) * valubytes.
Proof.
induction vs.
reflexivity.
simpl.
rewrite app_length.
rewrite IHvs.
rewrite valuset2bytesets_len.
reflexivity.
Qed.

Lemma valuset2bytesets_rec_nil: forall i,
valuset2bytesets_rec nil i = nil.
Proof. intros; destruct i; reflexivity. Qed.




Lemma firstn1 : forall A (l:list(list A)),
concat(firstn 1 l) = selN l 0 nil.
Proof.
intros.
induction l.
rewrite firstn_nil.
reflexivity.
simpl.
apply app_nil_r.
Qed.

Lemma concat_hom_O: forall A (l: list(list A)) i k,
Forall (fun sublist : list A => length sublist = k) l ->
i<= k -> 
firstn i (concat l) = firstn i (selN l 0 nil).
Proof.
intros.
induction l.
reflexivity.
simpl.
rewrite firstn_app_l.
reflexivity.
rewrite Forall_forall in H.
destruct H with (x:= a).
apply in_eq.
apply H0.
Qed.



Lemma div_eq: forall m n k, k < m -> (n * m + k)/m = n.
Proof.
intros.
rewrite Nat.div_add_l.
apply Nat.div_small in H.
rewrite H; symmetry; apply plus_n_O.
unfold not; intros; rewrite H0 in H; inversion H.
Qed.

Lemma maplatest_mapl2nel: forall A (l: list (list A)) def,
map (@latest A) (map (list2nelist def) l) = map (selN' 0 def) l.
Proof.
intros.
rewrite map_map.
unfold selN'.
replace (fun x : list A => ((list2nelist def) x)!!) with
  (fun x : list A => selN x 0 def).
reflexivity.
apply functional_extensionality.
intros; symmetry; apply latest_l2nel.
Qed.

Lemma bcombine_list_contr: forall a l, 
bcombine (byte2bytes a) (bcombine_list l) = bcombine_list (a::l).
Proof. intros; reflexivity. Qed.

(* Lemma list2valu2list: forall l, l<>nil -> valu2list (list2valu l) = l.
Proof. Admitted.

Lemma valu2list2valu: forall v, list2valu (valu2list v) = v.
Proof. Admitted.
 *)


Lemma cons_simpl: forall A a (l l': list A),
l = l' -> (a::l) = (a::l').
Proof. intros; rewrite H; reflexivity. Qed.

Definition cons' {A} (a: list A) b:= cons b a.

Lemma v2b_rec_nil: forall l i,
i = length l  ->
valuset2bytesets_rec (l::nil) i = map (list2nelist byte0) (map (cons' nil) l).
Proof.
induction l; intros.
rewrite H; reflexivity.
simpl.
destruct i.
inversion H.
simpl.
rewrite IHl.
reflexivity.
simpl in H.
inversion H; reflexivity.
Qed.

Lemma maplatest_v2b: forall  i l,
  l <> nil ->  length l <= i -> 
  (map (@latest byte) (valuset2bytesets_rec l i)) = 
  selN l 0 (byte0::nil).
Proof. Admitted.

(* Lemma mapfst_valuset2bytesets: forall i a vs,
length vs >  i ->
(map (@latest byte) (valuset2bytesets_rec (a::vs) i)) = a.
Proof.
induction i; intros.
simpl.
apply length_nil in H.
symmetry; apply H.
rewrite mapfst_v2b_unfold.
replace (S i - 1) with i by omega.
rewrite map_cons.
rewrite IHi.
Search cons selN skipn.
rewrite <- skipn_selN_skipn.
reflexivity.
omega.
rewrite skipn_length.
omega.
omega.
Qed. *)

(* Lemma v2b_rec_selN: forall i j l,
length l = i -> j < i ->
selN (valuset2bytesets_rec l i) j byteset0 = list2nelist byteset0 (map (selN' j byte0) l).
Proof.
induction i; intros.
inversion H0.
destruct l.
reflexivity.
destruct j.
reflexivity.
rewrite valuset2bytesets_rec_expand.
replace (S i - 1) with i by omega.
rewrite selN_cons.
rewrite IHi.
unfold list2nelist.
simpl.
rewrite map_map.
simpl.

simpl.
inversion H0.
rewrite <- IHi.
simpl.
simpl.
destruct j.
reflexivity.
unfold list2nelist in IHl.
destruct a.
simpl.
rewrite IHl. *)

(* Lemma skipn_v2b_rec_comm: forall l i j,
i < j -> length l = j ->
skipn i (valuset2bytesets_rec l j) = valuset2bytesets_rec (skipn i l) (j-i).
Proof.
induction l; intros.
destruct H0; inversion H.

destruct j. inversion H.
destruct i.
rewrite <- minus_n_O.
reflexivity.

simpl.
rewrite <- IHl.
destruct a.
simpl.
rewrite valuset2bytesets_rec_expand.
destruct j.
inversion H.
unfold selN'.
repeat rewrite map_cons.
rewrite skipn_nil.
rewrite valuset2bytesets_rec_expand.
simpl.
rewrite <- IHl.
simpl.
destruct i. reflexivity.
simpl.
rewrite <- minus_n_O; reflexivity.
simpl. *)


Lemma bsplit1_bsplit_list: forall sz (b: bytes (1 + (sz - 1))),
(bsplit1 1 (sz - 1) b
    :: bsplit_list (bsplit2 1 (sz - 1) b)) = bsplit_list b.
Proof.
intros.
simpl.
unfold bsplit1_dep, bsplit2_dep.
reflexivity.
Qed.

Lemma valuset2bytesets2valuset: forall vs, bytesets2valuset (valuset2bytesets vs) = vs.
Proof. Admitted.


Lemma bytesets2valuset2bytesets: forall bs, bs <> nil -> valuset2bytesets (bytesets2valuset bs) = bs.
Proof. Admitted.
