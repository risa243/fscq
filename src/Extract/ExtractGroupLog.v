Require Import List String.
Require Import StringMap.
Require Import Word Prog Pred AsyncDisk.
Require Import GoSemantics GoFacts GoHoare GoCompilationLemmas GoExtraction GoSepAuto GoTactics2.
Require Import Wrappers EnvBuild.
Import ListNotations.

Import Go.

Require Import GroupLog.

Local Open Scope string_scope.

Example compile_read : sigT (fun p => source_stmt p /\
  forall env lxp a ms,
  prog_func_call_lemma
    {|
      FArgs := [
        with_wrapper _;
        with_wrapper _;
        with_wrapper _
      ];
      FRet := with_wrapper _
    |}
    "mlog_read" MemLog.MLog.read env ->
  EXTRACT GLog.read lxp a ms
  {{ 0 ~>? (GLog.memstate * valu) *
     1 ~> lxp *
     2 ~> a *
     3 ~> ms }}
    p
  {{ fun ret => 0 ~> ret *
     1 ~>? FSLayout.log_xparams *
     2 ~>? nat *
     3 ~>? GLog.memstate }} // env).
Proof.
  unfold GLog.read, GLog.MSLL, GLog.mk_memstate.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
  compile_step.
Admitted.

Definition extract_env : Env.
  pose (env := StringMap.empty FunctionSpec).
  exact env.
Defined.