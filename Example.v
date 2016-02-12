Require Import PArith.
Require Import List.
Import List.ListNotations.
Open Scope positive.
Open Scope list.

Require Import Rustre.Common.
Require Import Rustre.Dataflow.Syntax.

Require Import Rustre.Dataflow.Memories.
Require Import Rustre.Dataflow.WellFormed.
Require Import Rustre.Dataflow.WellFormed.Decide.

(* TODO: not properly clocked... *)
Example eqns1 : list equation :=
  [
    EqFby 3 (Cint 0) (LAexp (Con Cbase 1 false) (Evar 2));
    EqDef 4 (CAexp Cbase (Emerge 1 (Eexp (Evar 2))
                                   (Eexp (Evar 3))));
    EqDef 2 (CAexp (Con Cbase 1 true)
                   (Eexp (Ewhen (Econst (Cint 7)) 1 true))
            )
(*   ;EqDef 1 (CAexp Cbase (Eexp (Econst (Cbool true)))) *)
  ].

Example node1 : node :=
  mk_node 1 1 4 eqns1.


Example eqns2 : list equation :=
  [
    EqFby 3 (Cint 0) (LAexp Cbase (Evar 2));
    EqApp 4 1 (LAexp Cbase (Evar 3));
    EqApp 2 1 (LAexp Cbase (Evar 1))
  ].

Example node2 : node :=
  mk_node 2 1 4 eqns2.

(** Scheduling *)

Example eqn1_well_sch: Is_well_sch (memories eqns1) 1 eqns1.
Proof.
  assert (well_sch (memories eqns1) 1 eqns1 = true) as HW by apply eq_refl.
  pose proof (well_sch_spec (memories eqns1) 1 eqns1) as HS.
  rewrite HW in HS.
  assumption.
Qed.

Example eqn2_well_sch: Is_well_sch (memories eqns2) 1 eqns2.
Proof.
  assert (well_sch (memories eqns2) 1 eqns2 = true) as HW by apply eq_refl.
  pose proof (well_sch_spec (memories eqns2) 1 eqns2) as HS.
  rewrite HW in HS.
  assumption.
Qed.

(** Translation *)
Require Import Rustre.Minimp.Syntax.
Require Import Rustre.Translation.

(* Eval cbv in (translate_node node1). *)

Example prog1 : stmt :=
  Comp (Ifte (Var 1) (Assign 2 (Const (Cint 7))) Skip)
       (Comp (Ifte (Var 1) (Assign 4 (Var 2))
                   (Assign 4 (State 3)))
             (Comp (Ifte (Var 1) Skip (AssignSt 3 (Var 2)))
                   Skip)).

Remark prog1_good : (translate_node node1).(c_step) = prog1.
Proof eq_refl.

Example reset1 : stmt :=
  translate_reset_eqns eqns1.

(* Eval cbv in (translate_node node2). *)

Example class2 : class :=
  {|
    c_name := 2;
    c_input := 1;
    c_output := 4;
    c_mems := [3];
    c_objs := [{| obj_inst := 2; obj_class := 1 |};
                {| obj_inst := 4; obj_class := 1 |}];
    c_step := Comp (Step_ap 2 1 2 (Var 1))
                   (Comp (Step_ap 4 1 4 (State 3))
                         (Comp (AssignSt 3 (Var 2))
                               Skip));
    c_reset := Comp (Reset_ap 1 2)
                    (Comp (Reset_ap 1 4)
                          (Comp (AssignSt 3 (Const (Cint 0)))
                                Skip))
  |}.

Remark prog2_good : translate_node node2 = class2.
Proof eq_refl.

(** Optimization *)

Require Import Rustre.Minimp.FuseIfte.

Example prog1' : stmt :=
  Ifte (Var 1)
       (Comp (Assign 2 (Const (Cint 7)))
             (Assign 4 (Var 2)))
       (Comp (Assign 4 (State 3))
             (AssignSt 3 (Var 2))).

Remark prog1'_is_fused: (ifte_fuse prog1 = prog1').
Proof eq_refl.

(* TODO: Show correctness of prog1' *)

(** Examples from paper *)

Section CodegenPaper.

  Require Import Nelist.


  (* Too complicated! *)
  Parameter Plus : operator.
  Axiom Plus_arity : get_arity Plus = Tcons Tint (Tcons Tint (Tout Tint)).

  Definition Plus_to_arrows (f: Z -> Z -> Z) : arrows (get_arity Plus).
    rewrite Plus_arity. exact f.
  Defined.

  Axiom Plus_interp : get_interp Plus = Plus_to_arrows BinInt.Z.add.

  Definition op_plus (x: lexp) (y: lexp) : lexp :=
    Eop Plus (necons x (nebase y)).

  Parameter Ifte_int : operator.
  Axiom Ifte_int_arity : get_arity Ifte_int
                         = Tcons Tbool (Tcons Tint (Tcons Tint (Tout Tint))).

  Definition Ifte_int_to_arrows
             (f: bool -> Z -> Z -> Z) : arrows (get_arity Ifte_int).
    rewrite Ifte_int_arity. exact f.
  Defined.

  Definition ifte {T: Set} (x: bool) (t: T) (f: T) : T := if x then t else f.
  Axiom Ifte_interp : get_interp Ifte_int = Ifte_int_to_arrows ifte.

  Definition op_ifte (x: lexp) (t: lexp) (f: lexp) : lexp :=
    Eop Ifte_int (necons x (necons t (nebase f))).




  (* Node names *)
  Definition n_counter     : ident := 1.
  Definition n_altcounters : ident := n_counter + 1.

(*
  node counter (initial, increment: int; restart: bool) returns (n: int)
  var c: int;
  let
    n = if restart then initial else c + increment;
    c = 0 fby n;
  tel

 *)

  (* counter: variable names *)
  Definition initial   : ident := 1.
  Definition increment : ident := 2.
  Definition restart   : ident := 3.
  Definition n         : ident := 4.
  Definition c         : ident := 5.

  Example counter_eqns : list equation :=
    [
      EqFby c (Cint 0) (LAexp Cbase (Evar n));
      EqDef n (CAexp Cbase (Eexp (op_ifte (Evar restart)
                                          (Evar initial)
                                          (op_plus (Evar c) (Econst (Cint 1))))))
    ].

  (* TODO: show that these equations Is_well_sch and Well_clocked;
           need multiple inputs *)

  (* TODO: multiple inputs: initial, increment, restart *)
  Example counter : node :=
    mk_node n_counter initial n counter_eqns.

  Eval cbv in translate_node counter.
  Eval cbv in ifte_fuse (c_step (translate_node counter)).
  Eval cbv in ifte_fuse (c_reset (translate_node counter)).


(*
  node altcounters (b: bool) returns (y: int)
  var n1, n2: int;
  let
    n1 = counter(0, 1, false);
    n2 = counter(0 whenot b, −1 whenot b, false whenot b);
    y = merge b (n1 when b) n2;
  tel
*)

  (* altcounters: variable names *)
  Definition b  : ident := 1.
  Definition n1 : ident := 2.
  Definition n2 : ident := 3.
  Definition y  : ident := 4.

  Example altcounters_eqns : list equation :=
    [
      EqDef y (CAexp Cbase
                     (Emerge b
                             (Eexp (Ewhen (Evar n1) b true))
                             (Eexp (Evar n2))));
      (* Add other inputs:
           Ewhen (Econst (Cint (-1))) b false
           Ewhen (Econst (Cbool false)) b false *)
      EqApp n2 n_counter (LAexp (Con Cbase b false)
                                (Ewhen (Econst (Cint 0)) b false));
      (* Add other inputs:
           Econst 1
           Econst false *)
      EqApp n1 n_counter (LAexp Cbase (Econst (Cint 0)))
    ].

  (* TODO: show that these equations Is_well_sch and Well_clocked;
           need multiple inputs *)

  Example altcounters : node :=
    mk_node n_altcounters b y altcounters_eqns.

  Eval cbv in translate_node altcounters.
  Eval cbv in ifte_fuse (c_step (translate_node altcounters)).


End CodegenPaper.