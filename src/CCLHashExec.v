Require Import CCLProg.
Require Import Hashmap.
Require Import Automation.

Theorem exec_hashmap_le : forall St T (p: @cprog St T)
                            G tid sigma_i sigma out,
    exec G tid (sigma_i, sigma) p out ->
    match out with
    | Finished _ sigma' _ => hashmap_le (Sigma.hm sigma) (Sigma.hm sigma')
    | Error => True
    end.
Proof.
  intros.
  remember (sigma_i, sigma).
  generalize dependent sigma.
  generalize dependent sigma_i.
  induction H; intros;
    match goal with
    | [ H: (_,_) = (_,_) |- _ ] =>
      inversion H; subst; clear H
    end; auto.
  - destruct sigma0.
    destruct p;
      repeat match goal with
             | [ H: context[match ?d with | _ => _ end] |- _ ] =>
               destruct d
             | [ H: StepTo _ _ = StepTo _ _ |- _ ] =>
               inversion H; subst; clear H
             | [ |- hashmap_le ?a ?a ] => reflexivity
             | _ => progress simpl in *
             | _ => congruence
             end.
  - repeat match goal with
           | [ sigma: Sigma St |- _ ] => destruct sigma; simpl in *
           end;
      try reflexivity;
      eauto.
    unfold hashmap_le.
    eexists.
    econstructor; eauto.
    constructor.
  - destruct out; eauto.
    etransitivity; eauto.
  - destruct sigma'; simpl in *.
    eauto.
  - destruct sigma0; simpl;
      reflexivity.
Qed.

(* Local Variables: *)
(* company-coq-local-symbols: (("Sigma" . ?Σ) ("sigma" . ?σ) ("sigma'" . (?σ (Br . Bl) ?'))) *)
(* End: *)