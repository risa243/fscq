Require Import Arith.
Require Import Omega.
Require Import FunctionalExtensionality.
Require Import Prog.
Require Import RelationClasses.
Require Import Morphisms.

Set Implicit Arguments.


(** ** Predicates *)

Definition pred := mem -> Prop.

Definition ptsto (a : addr) (v : valu) : pred :=
  fun m => m a = Some v /\ forall a', a <> a' -> m a' = None.
Infix "|->" := ptsto (at level 35) : pred_scope.
Bind Scope pred_scope with pred.
Delimit Scope pred_scope with pred.

Definition impl (p q : pred) : pred :=
  fun m => p m -> q m.
Infix "-p->" := impl (right associativity, at level 95) : pred_scope.

Definition and (p q : pred) : pred :=
  fun m => p m /\ q m.
Infix "/\" := and : pred_scope.

Definition or (p q : pred) : pred :=
  fun m => p m \/ q m.
Infix "\/" := or : pred_scope.

Definition foral_ A (p : A -> pred) : pred :=
  fun m => forall x, p x m.
Notation "'foral' x .. y , p" := (foral_ (fun x => .. (foral_ (fun y => p)) ..)) (at level 200, x binder, right associativity) : pred_scope.

Definition exis A (p : A -> pred) : pred :=
  fun m => exists x, p x m.
Notation "'exists' x .. y , p" := (exis (fun x => .. (exis (fun y => p)) ..)) : pred_scope.
Notation "a |->?" := (exists v, a |-> v)%pred (at level 35) : pred_scope.

Definition uniqpred A (p : A -> pred) (x : A) :=
  fun m => p x m /\ (forall (x' : A), p x' m -> x = x').
Notation "'exists' ! x .. y , p" := (exis (uniqpred (fun x => .. (exis (uniqpred (fun y => p))) ..))) : pred_scope.

Definition emp : pred :=
  fun m => forall a, m a = None.

Definition any : pred :=
  fun m => True.

Definition lift (P : Prop) : pred :=
  fun m => P.
Notation "[ P ]" := (lift P) : pred_scope.

Definition lift_empty (P : Prop) : pred :=
  fun m => P /\ forall a, m a = None.
Notation "[[ P ]]" := (lift_empty P) : pred_scope.

Definition pimpl (p q : pred) := forall m, p m -> q m.
Notation "p =p=> q" := (pimpl p%pred q%pred) (right associativity, at level 90).

Definition piff (p q : pred) : Prop := (p =p=> q) /\ (q =p=> p).
Notation "p <=p=> q" := (piff p%pred q%pred) (at level 90).

Definition pupd (p : pred) (a : addr) (v : valu) : pred :=
  fun m => exists m', p m' /\ m = upd m' a v.
Notation "p [ a <--- v ]" := (pupd p a v) (at level 0) : pred_scope.

Definition mem_disjoint (m1 m2:mem) :=
  ~ exists a v1 v2, m1 a = Some v1 /\ m2 a = Some v2.

Definition mem_union (m1 m2:mem) := fun a =>
  match m1 a with
  | Some v => Some v
  | None => m2 a
  end.

Definition sep_star (p1: pred) (p2: pred) :=
  fun m => exists m1 m2, m = mem_union m1 m2 /\ mem_disjoint m1 m2 /\ p1 m1 /\ p2 m2.
Infix "*" := sep_star : pred_scope.

Definition indomain (a: addr) (m: mem) :=
  exists v, m a = Some v.

Definition diskIs (m : mem) : pred := eq m.
Definition diskptsto (m : mem) (a : addr) (v : valu) := m a = Some v.
Notation "m @ a |-> v" := (diskptsto m a v) (a at level 34, at level 35).

Definition mem_except (m: mem) (a: addr) :=
  fun a' => if addr_eq_dec a' a then None else m a'.


Ltac deex := match goal with
               | [ H : ex _ |- _ ] => destruct H; intuition subst
             end.

Ltac pred_unfold :=
  unfold impl, and, or, foral_, exis, uniqpred, lift, pupd in *.
Ltac pred := pred_unfold;
  repeat (repeat deex; simpl in *;
    intuition (try (congruence || omega);
      try autorewrite with core in *; eauto); try subst).

Theorem pimpl_refl : forall p, p =p=> p.
Proof.
  pred.
Qed.

Hint Resolve pimpl_refl.

Theorem mem_disjoint_comm:
  forall m1 m2,
  mem_disjoint m1 m2 <-> mem_disjoint m2 m1.
Proof.
  split; unfold mem_disjoint, not; intros; repeat deex; eauto 10.
Qed.

Theorem mem_disjoint_assoc_1:
  forall m1 m2 m3,
  mem_disjoint m1 m2 ->
  mem_disjoint (mem_union m1 m2) m3 ->
  mem_disjoint m1 (mem_union m2 m3).
Proof.
  unfold mem_disjoint, mem_union; intuition; repeat deex.
  case_eq (m2 x); intros.
  - apply H. eauto.
  - rewrite H1 in H3.
    apply H0. repeat eexists; eauto. rewrite H2. eauto.
Qed.

Theorem mem_disjoint_assoc_2:
  forall m1 m2 m3,
  mem_disjoint m2 m3 ->
  mem_disjoint m1 (mem_union m2 m3) ->
  mem_disjoint (mem_union m1 m2) m3.
Proof.
  unfold mem_disjoint, mem_union; intuition; repeat deex.
  case_eq (m2 x); intros.
  - apply H. eauto.
  - case_eq (m1 x); intros.
    + apply H0. repeat eexists; eauto. rewrite H1. eauto.
    + rewrite H4 in H2. firstorder.
Qed.

Theorem mem_disjoint_union:
  forall m1 m2 m3,
  mem_disjoint (mem_union m1 m2) m3 ->
  mem_disjoint m2 m3.
Proof.
  unfold mem_disjoint, mem_union; intuition; repeat deex.
  apply H; exists x; destruct (m1 x); eauto.
Qed.

Theorem mem_disjoint_upd:
  forall m1 m2 a v v0,
  m1 a = Some v0 ->
  mem_disjoint m1 m2 ->
  mem_disjoint (upd m1 a v) m2.
Proof.
  unfold mem_disjoint, upd, not; intros; repeat deex;
    destruct (addr_eq_dec x a); subst; eauto 10.
Qed.

Theorem mem_union_comm:
  forall m1 m2,
  mem_disjoint m1 m2 ->
  mem_union m1 m2 = mem_union m2 m1.
Proof.
  unfold mem_disjoint, mem_union; intros; apply functional_extensionality; intros.
  case_eq (m1 x); case_eq (m2 x); intros; eauto; destruct H; eauto.
Qed.

Theorem mem_union_addr:
  forall m1 m2 a v,
  mem_disjoint m1 m2 ->
  m1 a = Some v ->
  mem_union m1 m2 a = Some v.
Proof.
  unfold mem_disjoint, mem_union; intros; rewrite H0; auto.
Qed.

Theorem mem_union_upd:
  forall m1 m2 a v v0,
  m1 a = Some v0 ->
  mem_union (upd m1 a v) m2 = upd (mem_union m1 m2) a v.
Proof.
  unfold mem_union, upd; intros; apply functional_extensionality; intros.
  destruct (addr_eq_dec x a); eauto.
Qed.

Theorem mem_union_assoc:
  forall m1 m2 m3,
  mem_disjoint m1 m2 ->
  mem_disjoint (mem_union m1 m2) m3 ->
  mem_union (mem_union m1 m2) m3 = mem_union m1 (mem_union m2 m3).
Proof.
  unfold mem_union, mem_disjoint; intros; apply functional_extensionality; intuition.
  destruct (m1 x); auto.
Qed.

Theorem sep_star_comm1:
  forall p1 p2,
  (p1 * p2 =p=> p2 * p1)%pred.
Proof.
  unfold pimpl, sep_star; pred.
  exists x0; exists x. intuition eauto using mem_union_comm. apply mem_disjoint_comm; auto.
Qed.

Theorem sep_star_comm:
  forall p1 p2,
  (p1 * p2 <=p=> p2 * p1)%pred.
Proof.
  unfold piff; split; apply sep_star_comm1.
Qed.

Theorem sep_star_assoc_1:
  forall p1 p2 p3,
  (p1 * p2 * p3 =p=> p1 * (p2 * p3))%pred.
Proof.
  unfold pimpl, sep_star; pred.
  exists x1; exists (mem_union x2 x0); intuition.
  apply mem_union_assoc; auto.
  apply mem_disjoint_assoc_1; auto.
  exists x2; exists x0; intuition eauto.
  eapply mem_disjoint_union; eauto.
Qed.

Theorem sep_star_assoc_2:
  forall p1 p2 p3,
  (p1 * (p2 * p3) =p=> p1 * p2 * p3)%pred.
Proof.
  unfold pimpl, sep_star; pred.
  exists (mem_union x x1); exists x2; intuition.
  rewrite mem_union_assoc; auto.
  apply mem_disjoint_comm. eapply mem_disjoint_union. apply mem_disjoint_comm.
  rewrite mem_union_comm. eauto. apply mem_disjoint_comm. eauto.
  apply mem_disjoint_assoc_2; eauto.
  apply mem_disjoint_assoc_2; eauto.
  repeat eexists; eauto.
  apply mem_disjoint_comm. eapply mem_disjoint_union.
  rewrite mem_union_comm; [|apply mem_disjoint_comm;eassumption].
  apply mem_disjoint_comm; assumption.
Qed.

Theorem sep_star_assoc:
  forall p1 p2 p3,
  (p1 * p2 * p3 <=p=> p1 * (p2 * p3))%pred.
Proof.
  split; [ apply sep_star_assoc_1 | apply sep_star_assoc_2 ].
Qed.

Local Hint Extern 1 =>
  match goal with
    | [ |- upd _ ?a ?v ?a = Some ?v ] => apply upd_eq; auto
  end.

Lemma pimpl_exists_l:
  forall T p q,
  (forall x:T, p x =p=> q) ->
  (exists x:T, p x) =p=> q.
Proof.
  firstorder.
Qed.

Lemma pimpl_exists_r:
  forall T p q,
  (exists x:T, p =p=> q x) ->
  (p =p=> exists x:T, q x).
Proof.
  firstorder.
Qed.

Lemma pimpl_exists_l_star:
  forall T p q r,
  ((exists x:T, p x * r) =p=> q) ->
  (exists x:T, p x) * r =p=> q.
Proof.
  unfold pimpl, sep_star, exis; intros.
  repeat deex.
  eapply H.
  do 3 eexists.
  intuition eauto.
Qed.

Lemma pimpl_exists_r_star:
  forall T p q,
  (exists x:T, p x * q) =p=> ((exists x:T, p x) * q).
Proof.
  unfold pimpl, sep_star, exis; intros.
  repeat deex.
  do 2 eexists.
  intuition eauto.
Qed.

Lemma pimpl_exists_l_and:
  forall T p q r,
  ((exists x:T, p x /\ r) =p=> q) ->
  (exists x:T, p x) /\ r =p=> q.
Proof.
  firstorder.
Qed.

Lemma pimpl_trans:
  forall a b c,
  (a =p=> b) ->
  (b =p=> c) ->
  (a =p=> c).
Proof.
  firstorder.
Qed.

Lemma piff_trans:
  forall a b c,
  (a <=p=> b) ->
  (b <=p=> c) ->
  (a <=p=> c).
Proof.
  unfold piff; intuition; eapply pimpl_trans; eauto.
Qed.

Lemma piff_comm:
  forall a b,
  (a <=p=> b) ->
  (b <=p=> a).
Proof.
  unfold piff; intuition.
Qed.

Lemma piff_refl:
  forall a,
  (a <=p=> a).
Proof.
  unfold piff; intuition.
Qed.

Lemma pimpl_apply:
  forall (p q:pred) m,
  (p =p=> q) ->
  p m ->
  q m.
Proof.
  firstorder.
Qed.

Lemma piff_apply:
  forall (p q:pred) m,
  (p <=p=> q) ->
  q m ->
  p m.
Proof.
  firstorder.
Qed.

Lemma pimpl_fun_l:
  forall (p:pred),
  (fun m => p m) =p=> p.
Proof.
  firstorder.
Qed.

Lemma pimpl_fun_r:
  forall (p:pred),
  p =p=> (fun m => p m).
Proof.
  firstorder.
Qed.

Lemma pimpl_sep_star:
  forall a b c d,
  (a =p=> c) ->
  (b =p=> d) ->
  (a * b =p=> c * d).
Proof.
  unfold pimpl, sep_star; intros.
  do 2 deex.
  do 2 eexists.
  intuition eauto.
Qed.

Lemma pimpl_and:
  forall a b c d,
  (a =p=> c) ->
  (b =p=> d) ->
  (a /\ b =p=> c /\ d).
Proof.
  firstorder.
Qed.

Lemma pimpl_or : forall p q p' q',
  p =p=> p'
  -> q =p=> q'
  -> p \/ q =p=> p' \/ q'.
Proof.
  firstorder.
Qed.

Lemma sep_star_lift_l:
  forall (a: Prop) (b c: pred),
  (a -> (b =p=> c)) ->
  b * [[a]] =p=> c.
Proof.
  unfold pimpl, lift_empty, sep_star; intros.
  repeat deex.
  assert (mem_union x x0 = x).
  apply functional_extensionality; unfold mem_union; intros.
  case_eq (x x1); pred.
  rewrite H. eauto.
Qed.

Lemma sep_star_lift_r':
  forall (b: Prop) (a c: pred),
  (a =p=> [b] /\ c) ->
  (a =p=> [[b]] * c).
Proof.
  unfold pimpl, lift_empty, and, sep_star; intros.
  exists (fun _ => None).
  exists m.
  intuition firstorder.
  unfold mem_disjoint. intuition. repeat deex. congruence.
Qed.

Lemma sep_star_lift_r:
  forall (a b: pred) (c: Prop),
  (a =p=> b /\ [c]) ->
  (a =p=> b * [[c]]).
Proof.
  intros.
  eapply pimpl_trans; [|apply sep_star_comm].
  apply sep_star_lift_r'.
  firstorder.
Qed.

Lemma pimpl_star_emp: forall p, p =p=> emp * p.
Proof.
  unfold sep_star, pimpl; intros.
  repeat eexists; eauto.
  unfold mem_union; eauto.
  unfold mem_disjoint; pred.
Qed.

Lemma star_emp_pimpl: forall p, emp * p =p=> p.
Proof.
  unfold sep_star, pimpl; intros.
  unfold emp in *; pred.
  assert (mem_union x x0 = x0).
  apply functional_extensionality; unfold mem_union; intros.
  case_eq (x x1); intuition. rewrite H1 in H0; pred.
  pred.
Qed.

Lemma emp_star: forall p, p <=p=> emp * p.
Proof.
  intros; split; [ apply pimpl_star_emp | apply star_emp_pimpl ].
Qed.

Lemma piff_star_r: forall a b c,
  (a <=p=> b) ->
  (a * c <=p=> b * c).
Proof.
  unfold piff, sep_star, pimpl; intuition;
    repeat deex; repeat eexists; eauto.
Qed.

Lemma piff_star_l: forall a b c,
  (a <=p=> b) ->
  (c * a <=p=> c * b).
Proof.
  unfold piff, sep_star, pimpl; intuition;
    repeat deex; repeat eexists; eauto.
Qed.

Lemma piff_l :
  forall p p' q,
  (p <=p=> p')
  -> (p' =p=> q)
  -> (p =p=> q).
Proof.
  firstorder.
Qed.

Lemma piff_r :
  forall p q q',
  (q <=p=> q')
  -> (p =p=> q')
  -> (p =p=> q).
Proof.
  firstorder.
Qed.

Lemma sep_star_lift2and:
  forall a b,
  (a * [[b]]) =p=> a /\ [b].
Proof.
  unfold sep_star, and, lift, lift_empty, pimpl.
  intros; repeat deex.
  assert (mem_union x x0 = x).
  apply functional_extensionality; intros.
  unfold mem_union. destruct (x x1); eauto.
  congruence.
Qed.

Lemma sep_star_and2lift:
  forall a b,
  (a /\ [b]) =p=> (a * [[b]]).
Proof.
  unfold sep_star, and, lift, lift_empty, pimpl.
  intros; repeat deex.
  do 2 eexists; intuition; eauto.
  - unfold mem_union.
    apply functional_extensionality.
    intros; destruct (m x); auto.
  - unfold mem_disjoint, not; intros.
    repeat deex.
    congruence.
Qed.

Lemma ptsto_valid:
  forall a v F m,
  (a |-> v * F)%pred m
  -> m a = Some v.
Proof.
  unfold sep_star, ptsto.
  intros; repeat deex.
  apply mem_union_addr; eauto.
Qed.

Lemma ptsto_upd:
  forall a v v0 F m,
  (a |-> v0 * F)%pred m ->
  (a |-> v * F)%pred (upd m a v).
Proof.
  unfold sep_star, upd; intros; repeat deex.
  exists (fun a' => if addr_eq_dec a' a then Some v else None).
  exists x0.
  split; [|split].
  - apply functional_extensionality; intro.
    unfold mem_union; destruct (addr_eq_dec x1 a); eauto.
    unfold ptsto in H1; destruct H1. rewrite H1; eauto.
  - unfold mem_disjoint in *. intuition. repeat deex.
    apply H. repeat eexists; eauto.
    unfold ptsto in H1; destruct H1.
    destruct (addr_eq_dec x1 a); subst; eauto.
    pred.
  - intuition eauto.
    unfold ptsto; intuition.
    destruct (addr_eq_dec a a); pred.
    destruct (addr_eq_dec a' a); pred.
Qed.

Lemma pimpl_and_split:
  forall a b c,
  (a =p=> b)
  -> (a =p=> c)
  -> (a =p=> b /\ c).
Proof.
  firstorder.
Qed.

Lemma pimpl_and_lift: forall (a b: pred) (c:Prop),
  (a =p=> b)
  -> c
  -> (a =p=> b /\ [c]).
Proof.
  firstorder.
Qed.

Lemma pimpl_or_l: forall (a b c: pred),
  (a =p=> c)
  -> (b =p=> c)
  -> (a \/ b =p=> c).
Proof.
  firstorder.
Qed.

Lemma pimpl_or_r: forall (a b c: pred),
  ((a =p=> b) \/ (a =p=> c))
  -> (a =p=> b \/ c).
Proof.
  firstorder.
Qed.

Lemma pimpl_any :
  forall p,
  p =p=> any.
Proof.
  firstorder.
Qed.

Lemma pimpl_emp_any :
  forall p,
  p =p=> emp * any.
Proof.
  intros.
  eapply pimpl_trans; [|apply pimpl_star_emp]; apply pimpl_any.
Qed.

Lemma eq_pimpl : forall a b,
  a = b
  -> (a =p=> b).
Proof.
  intros; subst; firstorder.
Qed.

Theorem diskIs_split : forall m a v,
  (m @ a |-> v)
  -> (diskIs m =p=> diskIs (mem_except m a) * a |-> v).
Proof.
  unfold pimpl, diskIs, sep_star, ptsto; intros; subst.
  exists (fun a' => if addr_eq_dec a' a then None else m0 a').
  exists (fun a' => if addr_eq_dec a' a then Some v else None).
  intuition.
  - unfold mem_union; apply functional_extensionality; intros.
    destruct (addr_eq_dec x a); subst; auto.
    destruct (m0 x); auto.
  - unfold mem_disjoint; unfold not; intros. repeat deex.
    destruct (addr_eq_dec x a); discriminate.
  - destruct (addr_eq_dec a a); congruence.
  - destruct (addr_eq_dec a' a); subst; congruence.
Qed.

Theorem diskIs_merge_upd : forall m a v,
  diskIs (mem_except m a) * a |-> v =p=> diskIs (upd m a v).
Proof.
  unfold pimpl, diskIs, sep_star, ptsto, upd; intros; subst; repeat deex.
  apply functional_extensionality; intros.
  case_eq (addr_eq_dec x a); intros; subst.
  - rewrite mem_union_comm; auto.
    erewrite mem_union_addr; eauto.
    apply mem_disjoint_comm; auto.
  - unfold mem_union, mem_except.
    destruct (addr_eq_dec x a); try discriminate.
    case_eq (m x); auto; intros.
    rewrite H4; auto.
Qed.

Theorem diskIs_merge_except : forall m a v,
  (m @ a |-> v)
  -> (diskIs (mem_except m a) * a |-> v =p=> diskIs m).
Proof.
  unfold pimpl, diskIs, sep_star, ptsto, upd; intros; subst; repeat deex.
  apply functional_extensionality; intros.
  unfold mem_union, mem_except.
  destruct (addr_eq_dec x a); subst; try congruence.
  destruct (m x); auto.
  rewrite H5; auto; discriminate.
Qed.

Theorem sep_star_indomain : forall p q a,
  (p =p=> indomain a) ->
  (p * q =p=> indomain a).
Proof.
  unfold pimpl, sep_star, indomain, mem_union.
  intros.
  repeat deex.
  edestruct H; eauto.
  rewrite H1.
  eauto.
Qed.

Theorem ptsto_indomain : forall a v,
  a |-> v =p=> indomain a.
Proof.
  firstorder.
Qed.

Theorem sep_star_ptsto_some : forall a v F m,
  (a |-> v * F)%pred m -> m a = Some v.
Proof.
  unfold ptsto, sep_star, mem_union.
  intros.
  repeat deex.
  rewrite H2.
  auto.
Qed.

Theorem sep_star_ptsto_indomain : forall a v F m,
  (a |-> v * F)%pred m -> indomain a m.
Proof.
  intros.
  eexists.
  eapply sep_star_ptsto_some.
  eauto.
Qed.

Definition pair_args_helper (A B C:Type) (f: A->B->C) (x: A*B) := f (fst x) (snd x).

Theorem sep_star_or_distr : forall a b c,
  (a * (b \/ c))%pred <=p=> (a * b \/ a * c)%pred.
Proof.
  split.
  - unfold sep_star, pimpl, or.
    intros; repeat deex.
    + left. do 2 eexists. eauto.
    + right. do 2 eexists. eauto.
  - apply pimpl_or_l.
    + apply pimpl_sep_star; [apply pimpl_refl|].
      apply pimpl_or_r; left; apply pimpl_refl.
    + apply pimpl_sep_star; [apply pimpl_refl|].
      apply pimpl_or_r; right; apply pimpl_refl.
Qed.

Instance piff_equiv : Equivalence piff.
  split.
  exact piff_refl.
  exact piff_comm.
  exact piff_trans.
Qed.

Instance pimpl_preorder : PreOrder pimpl.
  split.
  exact pimpl_refl.
  exact pimpl_trans.
Qed.

Instance sep_star_pimpl_proper :
  Proper (pimpl ==> pimpl ==> pimpl) sep_star.
Proof.
  intros a b H c d H'.
  apply pimpl_sep_star; assumption.
Qed.

Example pimpl_sep_star_rewrite : forall a b x y, a =p=> b
  -> (x * a * y =p=> x * b * y).
Proof.
  intros.
  rewrite H.
  reflexivity.
Qed.

Global Opaque sep_star.
