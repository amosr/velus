From Velus Require Import Common.
From Velus Require Import Operators.
From Velus Require Import CoreExpr.CESyntax.
From Velus Require Import Stc.StcSyntax.
From Velus Require Import Clocks.

From Velus Require Import Stc.StcIsSystem.
From Velus Require Import Stc.StcOrdered.

From Velus Require Import Stc.StcIsVariable.
From Velus Require Import Stc.StcIsLast.
From Velus Require Import Stc.StcIsDefined.

From Velus Require Import CoreExpr.CEIsFree.
From Velus Require Import Stc.StcIsFree.

From Coq Require Import List.
Import List.ListNotations.
Open Scope list_scope.

From Coq Require Import Omega.

Module Type STCWELLDEFINED
       (Import Ids   : IDS)
       (Import Op    : OPERATORS)
       (Import CESyn : CESYNTAX          Op)
       (Import Syn   : STCSYNTAX     Ids Op CESyn)
       (Import Syst  : STCISSYSTEM   Ids Op CESyn Syn)
       (Import Ord   : STCORDERED    Ids Op CESyn Syn Syst)
       (Import Var   : STCISVARIABLE Ids Op CESyn Syn)
       (Import Last  : STCISLAST     Ids Op CESyn Syn)
       (Import Def   : STCISDEFINED  Ids Op CESyn Syn Var Last)
       (Import CEIsF : CEISFREE      Ids Op CESyn)
       (Import Free  : STCISFREE     Ids Op CESyn Syn CEIsF).

  Inductive Is_well_sch (inputs: list ident) (mems: PS.t): list trconstr -> Prop :=
  | WSchNil:
      Is_well_sch inputs mems []
  | WSchTc:
      forall tc tcs,
        Is_well_sch inputs mems tcs ->
        (forall x,
            Is_free_in_tc x tc ->
            if PS.mem x mems
            then ~ Is_defined_in x tcs
            else Is_variable_in x tcs \/ In x inputs) ->
        (forall x, Is_defined_in_tc x tc -> ~ Is_defined_in x tcs) ->
        (forall s k,
            Is_sub_in_tc s k tc ->
            Forall (fun tc => forall k', Is_sub_in_tc s k' tc -> k' < k) tcs) ->
        Is_well_sch inputs mems (tc :: tcs).

  Definition Well_scheduled: program -> Prop :=
    Forall (fun s => Is_well_sch (map fst (s_in s)) (ps_from_list (map fst (s_lasts s))) (s_tcs s)).

  Lemma Is_well_sch_app:
    forall inputs mems tcs tcs',
      Is_well_sch inputs mems (tcs ++ tcs') ->
      Is_well_sch inputs mems tcs'.
  Proof.
    induction tcs; auto; simpl.
    inversion 1; auto.
  Qed.

  Lemma Is_last_in_not_Is_variable_in:
    forall tcs inputs mems x,
      Is_well_sch inputs mems tcs ->
      Is_last_in x tcs ->
      ~ Is_variable_in x tcs.
  Proof.
    induction tcs; intros * Wsch Last Var;
      inversion_clear Last as [?? IsLast|];
      inversion_clear Var as [?? IsVar|?? IsVar_in];
      inversion_clear Wsch as [|???? Defs].
    - inv IsLast; inv IsVar.
    - apply Is_variable_in_Is_defined_in in IsVar_in.
      eapply Defs; eauto.
      inv IsLast; constructor.
    - apply Is_variable_in_tc_Is_defined_in_tc in IsVar.
      eapply Defs; eauto.
      apply Is_defined_Is_variable_Is_last_in; auto.
    - eapply IHtcs; eauto.
  Qed.

  Lemma Reset_not_Step_in:
    forall tcs inputs mems i ck f,
      Is_well_sch inputs mems (TcReset i ck f :: tcs) ->
      ~ Step_in i tcs.
  Proof.
    inversion_clear 1 as [|????? Subs].
    unfold Step_in, Is_sub_in.
    rewrite Exists_exists.
    intros (tc' & Hin & IsStin).
    assert (Forall (fun tc => forall k', Is_sub_in_tc i k' tc -> k' < 0) tcs)
      by (apply Subs; auto using Is_sub_in_tc).
    eapply Forall_forall in Hin; eauto.
    apply Hin in IsStin.
    omega.
  Qed.

  Lemma Reset_not_Reset_in:
    forall tcs inputs mems i ck f,
      Is_well_sch inputs mems (TcReset i ck f :: tcs) ->
      ~ Reset_in i tcs.
  Proof.
    inversion_clear 1 as [|????? Subs].
    unfold Reset_in, Is_sub_in.
    rewrite Exists_exists.
    intros (tc' & Hin & IsStin).
    assert (Forall (fun tc => forall k', Is_sub_in_tc i k' tc -> k' < 0) tcs)
      by (apply Subs; auto using Is_sub_in_tc).
    eapply Forall_forall in Hin; eauto.
    apply Hin in IsStin.
    omega.
  Qed.

   (** The [normal_args] predicate defines a normalization condition on
      node arguments -- those that are not on the base clock can only
      be instantiated with constants or variables -- that is necessary
      for correct generation of Obc/Clight.

      To see why this is necessary. Consider the NLustre trconstr: y =
            f(1, 3 when ck / x)

      with x on the clock ck, and y on the base clock. The generated
            Obc code is y := f(1, 3 / x)

      which has no semantics when ck = false, since x = None then 3 /
      x is not given a meaning.

      Consider what would happen were the semantics of 3 / x =
      None. There are two possible problems.

      If x is a local variable, then x = None in Obc implies that x =
      VUndef in Clight and 3 / VUndef has no semantics. I.e., the Obc
      program having a semantics would not be enough to guarantee that
      the Clight program generated from it does.

      If x is a state variable, then x = None in Obc implies that x
      could be anything in Clight (though it would be defined since
      state variables are stored in a global structure). We might then
      prove that x is never 0 (when ck = true) in the original Lustre
      program. This would guarantee the absence of division by zero in
      the generated Obc (since x is None when ck = false), but not in
      the generated Clight code; since None in Obc means "don't care"
      in Clight, x may well contain the value 0 when ck is false (for
      instance, if ck = false at the first reaction).
 *)


  Inductive normal_args_tc (P: program) : trconstr -> Prop :=
  | CTcDef:
      forall x ck e,
        normal_args_tc P (TcDef x ck e)
  | CTcNext:
      forall x ck e,
        normal_args_tc P (TcNext x ck e)
  | CTcReset:
      forall s ck f,
        normal_args_tc P (TcReset s ck f)
  | CTcCall:
      forall s xs ck rst f es b P',
        find_system f P = Some (b, P') ->
        Forall2 noops_exp (map dck b.(s_in)) es ->
        normal_args_tc P (TcCall s xs ck rst f es).

  Definition normal_args_system (P: program) (s: system) : Prop :=
    Forall (normal_args_tc P) s.(s_tcs).

  Fixpoint normal_args (P: list system) : Prop :=
    match P with
    | [] => True
    | b :: P' => normal_args_system P b /\ normal_args P'
    end.

  Lemma normal_args_system_cons:
    forall system P,
      normal_args_system (system :: P) system ->
      ~ Is_system_in system.(s_name) system.(s_tcs) ->
      normal_args_system P system.
  Proof.
    intros system P Hnarg Hord.
    apply Forall_forall.
    intros tc Hin.
    destruct tc; eauto using normal_args_tc.
    apply Forall_forall with (2:=Hin) in Hnarg.
    inversion_clear Hnarg as [| | |???????? Hfind Hnargs].
    rewrite find_system_other in Hfind;
      eauto using normal_args_tc.
    intro; subst; apply Hord.
    apply Exists_exists.
    eexists; intuition eauto using Is_system_in_tc.
  Qed.

  Definition Well_defined (P: program) : Prop :=
    Ordered_systems P /\ Well_scheduled P /\ normal_args P.

  Inductive Step_with_reset_spec: list trconstr -> Prop :=
  | Step_with_reset_nil:
      Step_with_reset_spec []
  | Step_with_reset_TcDef:
      forall x ck e tcs,
        Step_with_reset_spec tcs ->
        Step_with_reset_spec (TcDef x ck e :: tcs)
  | Step_with_reset_TcNext:
      forall x ck e tcs,
        Step_with_reset_spec tcs ->
        Step_with_reset_spec (TcNext x ck e :: tcs)
  | Step_with_reset_TcReset:
      forall i ck f tcs,
        Step_with_reset_spec tcs ->
        Step_with_reset_spec (TcReset i ck f :: tcs)
  | Step_with_reset_TcCall:
      forall i xs ck (rst: bool) f es tcs,
        Step_with_reset_spec tcs ->
        (if rst then Reset_in i tcs else ~ Reset_in i tcs) ->
        Step_with_reset_spec (TcCall i xs ck rst f es :: tcs).

  Lemma Step_with_reset_spec_app:
    forall tcs tcs',
      Step_with_reset_spec (tcs ++ tcs') ->
      Step_with_reset_spec tcs'.
  Proof.
    induction tcs; auto; simpl.
    inversion 1; auto.
  Qed.

  Lemma Step_not_Step_Reset_in:
    forall tcs inputs mems i ys ck rst f es,
      Is_well_sch inputs mems (TcCall i ys ck rst f es :: tcs) ->
      Step_with_reset_spec (TcCall i ys ck rst f es :: tcs) ->
      ~ Step_in i tcs
      /\ if rst then Reset_in i tcs else ~ Reset_in i tcs.
  Proof.
    inversion_clear 1 as [|????? Subs].
    inversion_clear 1.
    split; auto.
    setoid_rewrite Exists_exists.
    intros (tc' & Hin & IsStin).
    assert (Forall (fun tc => forall k', Is_sub_in_tc i k' tc -> k' < 1) tcs)
        by (apply Subs; auto using Is_sub_in_tc).
    eapply Forall_forall in Hin; eauto.
    apply Hin in IsStin.
    omega.
  Qed.

  Lemma Is_well_sch_Step_with_reset_spec:
    forall tcs inputs mems,
      (forall j rst, Step_with_reset_in j rst tcs ->
                if rst then Reset_in j tcs else ~ Reset_in j tcs) ->
      Is_well_sch inputs mems tcs ->
      Step_with_reset_spec tcs.
  Proof.
    induction tcs as [|[]]; intros * Spec WSCH;
      inversion_clear WSCH as [|??? Free Def Subs];
      constructor;
      clear Free Def;
      try (eapply IHtcs; eauto; intros * Step; specialize (Spec j rst));
      try (setoid_rewrite Step_with_reset_in_cons_not_call in Spec; [|discriminate]).
    - apply Spec in Step.
      destruct rst.
      + inversion_clear Step as [?? Step'|]; auto; inv Step'.
      + intro; apply Step; right; auto.
    - apply Spec in Step.
      destruct rst.
      + inversion_clear Step as [?? Step'|]; auto; inv Step'.
      + intro; apply Step; right; auto.
    - assert (j <> i).
      { assert (Is_sub_in_tc i 0 (TcReset i c i0)) as Sub by constructor.
        apply Subs in Sub.
        eapply Forall_Exists, Exists_exists in Sub as (?&?& SubSpec & Step_tc); eauto.
        inv Step_tc; intro; subst.
        assert (1 < 0) by (apply SubSpec; constructor).
        omega.
      }
      apply Spec in Step.
      destruct rst.
      + inversion_clear Step as [?? Step'|]; auto; inv Step'.
        congruence.
      + intro; apply Step; right; auto.
    - assert (j <> i).
      { assert (Is_sub_in_tc i 1 (TcCall i i0 c b i1 l)) as Sub by constructor.
        apply Subs in Sub.
        eapply Forall_Exists, Exists_exists in Sub as (?&?& SubSpec & Step_tc); eauto.
        inv Step_tc; intro; subst.
        assert (1 < 1) by (apply SubSpec; constructor).
        omega.
      }
      rewrite Step_with_reset_in_cons_call in Spec; auto.
      apply Spec in Step.
      destruct rst.
      + inversion_clear Step as [?? Step'|]; auto; inv Step'.
      + intro; apply Step; right; auto.
    - assert (Step_with_reset_in i b (TcCall i i0 c b i1 l :: tcs)) as Step
          by (left; constructor).
      apply Spec in Step.
      destruct b.
      + inversion_clear Step as [?? Step'|]; auto; inv Step'.
      + intro; apply Step; right; auto.
  Qed.

  Module PN_as_OT := OrdersEx.PairOrderedType OrdersEx.Positive_as_OT OrdersEx.Nat_as_OT.
  Module PNS := MSetList.Make PN_as_OT.

  Section Decide.

    Variable mems : PS.t.

    (* TODO: rewrite using a strong specification?  *)

    Open Scope bool_scope.

    Definition check_var (defined: PS.t) (variables: PS.t) (x: ident) : bool :=
      if PS.mem x mems
      then negb (PS.mem x defined)
      else PS.mem x variables.

    Lemma check_var_spec:
      forall defined variables x,
        check_var defined variables x = true
        <->
        (PS.In x mems -> ~PS.In x defined)
        /\ (~PS.In x mems -> PS.In x variables).
    Proof.
      (*  TODO: how to automate all of this? *)
      intros defined variables x.
      unfold check_var.
      split.
      - intro Hif.
        split; intro Hin.
        + apply PS.mem_spec in Hin.
          rewrite Hin, Bool.negb_true_iff in Hif.
          apply PSP.Dec.F.not_mem_iff in Hif. exact Hif.
        + apply PSP.Dec.F.not_mem_iff in Hin.
          rewrite Hin, PS.mem_spec in Hif. exact Hif.
      - destruct 1 as [Hin Hnin].
        destruct PSP.In_dec with x mems as [H|H].
        + assert (PS.mem x mems = true) as H' by auto.
          rewrite H', Bool.negb_true_iff, <-PSP.Dec.F.not_mem_iff.
          now apply Hin with (1:=H).
        + assert (PS.mem x mems = false) as H' by now apply PSP.Dec.F.not_mem_iff.
          rewrite H', PS.mem_spec.
          now apply Hnin with (1:=H).
    Qed.

    Definition sub_tc (tc: trconstr) : option (ident * nat) :=
      match tc with
      | TcReset s _ _ => Some (s, 0)
      | TcCall s _ _ _ _ _ => Some (s, 1)
      | _ => None
      end.

    Lemma Is_sub_in_sub_tc:
      forall tc i k,
        Is_sub_in_tc i k tc <-> sub_tc tc = Some (i, k).
    Proof.
      destruct tc; simpl; split; try inversion_clear 1; auto using Is_sub_in_tc.
    Qed.

    Definition check_sub (i: ident) (k: nat) (sk: ident * nat) : bool :=
      if ident_eqb (fst sk) i then Nat.ltb (snd sk) k else true.

    Lemma check_sub_spec:
      forall i k i' k',
        check_sub i k (i', k') = true
        <->
        (i = i' -> k' < k).
    Proof.
      intros; unfold check_sub; simpl.
      split.
      - intros * E Tc; subst.
        rewrite ident_eqb_refl in E.
        apply Nat.ltb_lt; auto.
      - intros Spec.
        destruct (ident_eqb i' i) eqn: E; auto.
        apply Nat.ltb_lt, Spec.
        symmetry; apply ident_eqb_eq; auto.
    Qed.

    Definition check_tc (tc: trconstr) (acc: bool * PS.t * PS.t * PNS.t) : bool * PS.t * PS.t * PNS.t :=
      match acc with
      | (true, defs, vars, subs) =>
        let xs := defined_tc tc in
        let b := PS.for_all (check_var defs vars) (free_in_tc tc PS.empty)
                            && negb (existsb (fun x => PS.mem x defs) xs) in
        let defs := ps_adds xs defs in
        let vars := variables_tc vars tc in
        match sub_tc tc with
        | Some (i, k) =>
          (PNS.for_all (check_sub i k) subs && b,
           defs, vars, PNS.add (i, k) subs)
        | None => (b, defs, vars, subs)
        end
      | (false, _, _, _) => (false, PS.empty, PS.empty, PNS.empty)
      end.

    Definition well_sch (args: idents) (tcs: list trconstr) : bool :=
      fst (fst (fst (fold_right check_tc (true,
                                          PS.empty,
                                          ps_from_list args,
                                          PNS.empty) tcs))).

    Lemma PS_not_for_all_spec:
      forall (s : PS.t) (f : BinNums.positive -> bool),
        SetoidList.compat_bool PS.E.eq f ->
        (PS.for_all f s = false <-> ~ PS.For_all (fun x => f x = true) s).
    Proof.
      intros s f HSL.
      split.
      - intros Hfa HFa.
        apply (PS.for_all_spec _ HSL) in HFa.
        rewrite Hfa in HFa.
        discriminate.
      - intro HFa.
        apply Bool.not_true_iff_false.
        intro Hfa; apply HFa.
        apply (PS.for_all_spec _ HSL).
        assumption.
    Qed.

    Lemma pair_tc:
      forall A B (x y: A * B),
        RelationPairs.RelProd Logic.eq Logic.eq x y <-> x = y.
    Proof.
      split; intros * E; subst; auto.
      destruct x, y.
      inversion_clear E as [Fst Snd]; inv Fst; inv Snd; simpl in *; subst; auto.
    Qed.

    Lemma PNS_compat:
      forall A (f: (positive * nat) -> A),
        Morphisms.Proper (Morphisms.respectful (RelationPairs.RelProd Logic.eq Logic.eq) Logic.eq) f.
    Proof.
      intros * x y E.
      apply pair_tc in E; subst; auto.
    Qed.
    Hint Resolve PNS_compat.

    Lemma PNS_not_for_all_spec:
      forall (s : PNS.t) (f : positive * nat -> bool),
        PNS.for_all f s = false <-> ~ PNS.For_all (fun x => f x = true) s.
    Proof.
      split.
      - intros Hfa HFa.
        apply PNS.for_all_spec in HFa; auto.
        rewrite Hfa in HFa.
        discriminate.
      - intro HFa.
        apply Bool.not_true_iff_false.
        intro Hfa; apply HFa.
        apply PNS.for_all_spec; auto.
    Qed.

    (* Lemma in_fold_left_add: *)
    (*   forall x xs S, *)
    (*     PS.In x (fold_left (fun S' x => PS.add x S') xs S) *)
    (*     <-> *)
    (*     In x xs \/ PS.In x S. *)
    (* Proof. *)
    (*   induction xs as [|y xs IH]. *)
    (*   split; intro H; simpl in *; *)
    (*     intuition. *)
    (*   intro S; split; intro H. *)
    (*   - apply IH in H. *)
    (*     destruct H. *)
    (*     now left; constructor (assumption). *)
    (*     apply PS.add_spec in H; simpl; intuition. *)
    (*   - simpl; apply IH; simpl in H; intuition. *)
    (* Qed. *)

    Lemma free_spec:
      forall tcs args defs vars tc x,
        (forall x, PS.In x defs <-> Is_defined_in x tcs) ->
        (forall x, PS.In x vars <-> Is_variable_in x tcs \/ In x args) ->
        PS.For_all (fun x => check_var defs vars x = true) (free_in_tc tc PS.empty) ->
        Is_free_in_tc x tc ->
        if PS.mem x mems then ~ Is_defined_in x tcs else Is_variable_in x tcs \/ In x args.
    Proof.
      intros * DefSpec VarSpec E Hfree.
      apply free_in_tc_spec', E, check_var_spec in Hfree as (Hin & Hnin).
      destruct (PS.mem x mems) eqn: Mem.
      - rewrite <-DefSpec; apply PSE.MP.Dec.F.mem_iff, Hin in Mem; auto.
      - rewrite <-VarSpec; apply PSE.MP.Dec.F.not_mem_iff, Hnin in Mem; auto.
    Qed.

    Lemma def_spec:
      forall tcs defs tc x,
        (forall x, PS.In x defs <-> Is_defined_in x tcs) ->
        existsb (fun x => PS.mem x defs) (defined_tc tc) = false ->
        Is_defined_in_tc x tc ->
        ~ Is_defined_in x tcs.
    Proof.
      intros * DefSpec E Hdef Hdefs.
      apply DefSpec in Hdefs; apply Is_defined_in_defined_tc in Hdef.
      apply In_nth with (d := Ids.default) in Hdef as (?&?&?); subst.
      eapply existsb_nth with (d := Ids.default) in E; eauto.
      apply PSE.MP.Dec.F.not_mem_iff in E; auto.
    Qed.

    Lemma check_var_compat:
      forall defined variables,
        SetoidList.compat_bool PS.E.eq (check_var defined variables).
    Proof.
      intros defined variables x y Htc.
      unfold PS.E.eq in Htc.
      rewrite Htc.
      reflexivity.
    Qed.
    Hint Resolve check_var_compat.

    Lemma not_well_sch_vars_defs_spec:
      forall tcs args defs vars tc,
         (forall x, PS.In x defs <-> Is_defined_in x tcs) ->
         (forall x, PS.In x vars <-> Is_variable_in x tcs \/ In x args) ->
         PS.for_all (check_var defs vars) (free_in_tc tc PS.empty) &&
                 negb (existsb (fun x => PS.mem x defs) (defined_tc tc)) = false ->
        ~ Is_well_sch args mems (tc :: tcs).
    Proof.
      intros * DefSpec VarSpec E Wsch.
      inversion_clear Wsch as [|??? Hfree Hdefs].
      apply Bool.andb_false_iff in E as [E|E].
      - apply PS_not_for_all_spec in E; auto.
        apply E; intros x Hin; apply free_in_tc_spec' in Hin.
        apply Hfree in Hin.
        apply check_var_spec; split.
        + rewrite PSE.MP.Dec.F.mem_iff; intro Hin'; rewrite Hin' in Hin.
          now rewrite DefSpec.
        + rewrite PSE.MP.Dec.F.not_mem_iff; intro Hin'; rewrite Hin' in Hin.
          now rewrite VarSpec.
      - apply Bool.negb_false_iff, existsb_exists in E as (?& Hin & Hin').
        apply Is_defined_in_defined_tc in Hin.
        apply PSE.MP.Dec.F.mem_iff, DefSpec in Hin'.
        eapply Hdefs; eauto.
    Qed.

    Lemma Is_defined_in_adds_defined_tc:
      forall tcs defs tc x,
        (forall x, PS.In x defs <-> Is_defined_in x tcs) ->
        (PS.In x (ps_adds (defined_tc tc) defs) <-> Is_defined_in x (tc :: tcs)).
    Proof.
      intros * DefSpec; split; intro Hin;
        [apply ps_adds_spec in Hin as [|]|apply ps_adds_spec; inv Hin];
        try (now left; apply Is_defined_in_defined_tc; auto);
        try (now right; apply DefSpec; auto); auto.
    Qed.

    Lemma Is_variable_in_variables_tc:
      forall tcs args vars tc x,
        (forall x, PS.In x vars <-> Is_variable_in x tcs \/ In x args) ->
        (PS.In x (variables_tc vars tc) <-> Is_variable_in x (tc :: tcs) \/ In x args).
    Proof.
      intros * VarSpec; split; intro Hin.
      - apply variables_tc_empty in Hin as [Hin|Hin].
        + destruct tc; simpl in *; try (contradict Hin; apply not_In_empty).
          *{ apply PSE.MP.Dec.F.add_iff in Hin as [|Hin]; subst.
             - left; left; constructor.
             - contradict Hin; apply not_In_empty.
           }
          *{ apply ps_adds_spec in Hin as [|Hin].
             - left; left; constructor; auto.
             - contradict Hin; apply not_In_empty.
           }
        + apply VarSpec in Hin as [|]; intuition.
          left; right; auto.
      - apply variables_tc_empty; destruct Hin as [Hin|].
        + inversion_clear Hin as [?? Hin'|].
          *{ destruct tc; simpl; inv Hin'.
             - rewrite PSE.MP.Dec.F.add_iff; auto.
             - rewrite ps_adds_spec; auto.
           }
          * rewrite VarSpec; auto.
        + rewrite VarSpec; auto.
    Qed.


    Lemma well_sch_pre_spec:
      forall args tcs ok defs vars subs,
        fold_right check_tc (true,
                             PS.empty,
                             ps_from_list args,
                             PNS.empty) tcs = (ok, defs, vars, subs) ->
        if ok
        then
          Is_well_sch args mems tcs
          /\ (forall x, PS.In x defs <-> Is_defined_in x tcs)
          /\ (forall x, PS.In x vars <-> Is_variable_in x tcs \/ In x args)
          /\ (forall i k, PNS.In (i, k) subs <-> Is_sub_in i k tcs)
        else
          ~Is_well_sch args mems tcs.
    Proof.
      induction tcs as [|tc].
      - simpl; inversion_clear 1; intuition; try (now constructor);
          repeat match goal with
                 | H:PS.In _ PS.empty |- _ => apply PS.empty_spec in H; contradiction
                 | H:PNS.In _ PNS.empty |- _ => apply PNS.empty_spec in H; contradiction
                 | H:Is_defined_in _ nil |- _ => inversion H
                 | H:Is_variable_in _ nil |- _ => inversion H
                 | H:Is_sub_in _ _ nil |- _ => inversion H
                 | H: context[ps_from_list _] |- _ =>
                   apply ps_from_list_In in H
                 | _ => intuition
                 end.
        apply ps_from_list_In; auto.
      - simpl; intros * HH.
        destruct (fold_right check_tc (true, PS.empty, ps_from_list args, PNS.empty) tcs)
          as [[[ok' defs'] vars'] subs'].
        specialize (IHtcs ok' defs'  vars' subs' eq_refl).
        simpl in HH.
        destruct ok'.
        + destruct IHtcs as (Wsch & DefSpec & VarSpec & SubSpec).
          assert (forall x, PS.In x (ps_adds (defined_tc tc) defs') <-> Is_defined_in x (tc :: tcs))
            by (intros; eapply Is_defined_in_adds_defined_tc; eauto).
          assert (forall x, PS.In x (variables_tc vars' tc) <-> Is_variable_in x (tc :: tcs) \/ In x args)
            by (intros; eapply Is_variable_in_variables_tc; eauto).
          destruct (sub_tc tc) as [(i, k)|] eqn: St.
          *{ destruct ok; inversion HH as [E]; clear HH.
             - apply Bool.andb_true_iff in E as (E & E');
                 apply Bool.andb_true_iff in E' as (E' & E'').
               apply PNS.for_all_spec in E; auto.
               apply PS.for_all_spec in E'; auto.
               apply Bool.negb_true_iff in E''.
               split; [|split; [|split]]; auto.
               + constructor; auto.
                 * intros; eapply free_spec; eauto.
                 * intros; eapply def_spec; eauto.
                 * intros * Hin; apply Is_sub_in_sub_tc in Hin; rewrite Hin in St; inv St.
                   apply Forall_forall; intros.
                   assert (Is_sub_in i k' tcs) as Hst
                       by (apply Exists_exists; eexists; intuition; eauto).
                   apply SubSpec in Hst; apply E in Hst.
                   apply check_sub_spec in Hst; auto.
               + rewrite <-Is_sub_in_sub_tc in St.
                 intros i' k'; split; rewrite PNS.add_spec.
                 *{ intros [Tc|Hin].
                    - apply pair_tc in Tc; inv Tc; left; auto.
                    - apply SubSpec in Hin; right; auto.
                  }
                 *{ rewrite pair_tc; inversion_clear 1 as [?? St'|].
                    - inv St; inv St'; auto.
                    - right; apply SubSpec; auto.
                  }

             - apply Bool.andb_false_iff in E as [E|];
                 [|eapply not_well_sch_vars_defs_spec; eauto].
               inversion_clear 1 as [|????? Hsubs].
               rewrite <-Is_sub_in_sub_tc in St.
               apply Hsubs in St.
               apply PNS_not_for_all_spec in E; apply E; clear E.
               intros (i', k') Hin.
               apply check_sub_spec; intros; subst.
               apply SubSpec in Hin.
               eapply Forall_Exists, Exists_exists in Hin as (?&?& Spec & St'); eauto; auto.
           }
          *{ destruct ok; inversion HH as [E].
             - apply Bool.andb_true_iff in E as (E & E').
               apply PS.for_all_spec in E; try apply check_var_compat.
               apply Bool.negb_true_iff in E'.
               split; [|split; [|split]]; auto.
               + constructor; auto.
                 * intros; eapply free_spec; eauto.
                 * intros; eapply def_spec; eauto.
                 * intros * Hin; apply Is_sub_in_sub_tc in Hin; rewrite Hin in St; inv St.
               + subst; setoid_rewrite SubSpec.
                 split.
                 * right; auto.
                 * rewrite <-not_Some_is_None in St.
                   specialize (St (i, k)).
                   rewrite <-Is_sub_in_sub_tc in St.
                   inversion 1; auto; contradiction.
             - eapply not_well_sch_vars_defs_spec; eauto.
           }

        + inv HH; inversion 1; auto.
    Qed.

    Lemma well_sch_spec:
      forall args eqns,
        if well_sch args eqns
        then Is_well_sch args mems eqns
        else ~ Is_well_sch args mems eqns.
    Proof.
      intros args eqns.
      pose proof (well_sch_pre_spec args eqns) as Spec.
      unfold well_sch.
      destruct (fold_right check_tc
                  (true, PS.empty, ps_from_list args, PNS.empty) eqns)
        as [[[ok defs] vars] subs]; simpl.
      specialize (Spec ok defs vars subs eq_refl).
      destruct ok; intuition.
    Qed.

    Lemma Is_well_sch_by_refl:
      forall args eqns,
        well_sch args eqns = true <-> Is_well_sch args mems eqns.
    Proof.
      intros args eqns.
      pose proof (well_sch_spec args eqns) as Hwss.
      split; intro H.
      rewrite H in Hwss; assumption.
      destruct (well_sch args eqns); [reflexivity|].
      exfalso; apply Hwss; apply H.
    Qed.

    Lemma well_sch_dec:
      forall args eqns,
        {Is_well_sch args mems eqns} + {~ Is_well_sch args mems eqns}.
    Proof.
      intros args eqns.
      pose proof (well_sch_spec args eqns) as Hwss.
      destruct (well_sch args eqns); [left|right]; assumption.
    Qed.

  End Decide.

End STCWELLDEFINED.

Module StcWellDefinedFun
       (Ids   : IDS)
       (Op    : OPERATORS)
       (CESyn : CESYNTAX          Op)
       (Syn   : STCSYNTAX     Ids Op CESyn)
       (Syst  : STCISSYSTEM   Ids Op CESyn Syn)
       (Ord   : STCORDERED    Ids Op CESyn Syn Syst)
       (Var   : STCISVARIABLE Ids Op CESyn Syn)
       (Last  : STCISLAST     Ids Op CESyn Syn)
       (Def   : STCISDEFINED  Ids Op CESyn Syn Var Last)
       (CEIsF : CEISFREE      Ids Op CESyn)
       (Free  : STCISFREE     Ids Op CESyn Syn CEIsF)
<: STCWELLDEFINED Ids Op CESyn Syn Syst Ord Var Last Def CEIsF Free.
  Include STCWELLDEFINED Ids Op CESyn Syn Syst Ord Var Last Def CEIsF Free.
End StcWellDefinedFun.