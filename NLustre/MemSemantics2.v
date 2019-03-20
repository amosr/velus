Require Import List.
Import List.ListNotations.
Open Scope list_scope.
Require Import Coq.Sorting.Permutation.
Require Import Coq.Arith.Compare_dec.

Require Import Coq.FSets.FMapPositive.
Require Import Velus.Common.
Require Import Velus.Operators.
Require Import Velus.Clocks.
Require Import Velus.RMemory.
Require Import Velus.NLustre.Stream.
Require Import Velus.NLustre.NLExprSyntax.
Require Import Velus.NLustre.NLSyntax.
Require Import Velus.NLustre.IsVariable.
Require Import Velus.NLustre.IsDefined.
Require Import Velus.NLustre.NLExprSemantics.
Require Import Velus.NLustre.NLSemantics.
Require Import Velus.NLustre.NLInterpretor.
Require Import Velus.NLustre.Ordered.
Require Import Velus.NLustre.Memories.
Require Import Velus.NLustre.IsFree.
Require Import Velus.NLustre.NoDup.

Set Implicit Arguments.

(** * The NLustre+Memory semantics *)

(**

  We provide a "non-standard" dataflow semantics where the state
  introduced by an [fby] is kept in a separate [memory] of
  streams. The only difference is therefore in the treatment of the
  [fby].

 *)


(* XXX: Is this comment still relevant?

   NB: The history H is not really necessary here. We could just as well
       replay all the semantic definitions using a valueEnv N ('N' for now),
       since all the historical information is in ms. This approach would
       have two advantages:

       1. Conceptually cleanliness: N corresponds more or less to the
          temporary variables in the Obc implementation (except that it
          would also contain values for variables defined by EqFby).

       2. No index needed to access values in when reasoning about
          translation correctness.

       But this approach requires more uninteresting definitions and
       and associated proofs of properties, and a longer proof of equivalence
       with sem_node: too much work for too little gain.
 *)

Module Type MEMSEMANTICS
       (Import Ids     : IDS)
       (Import Op      : OPERATORS)
       (Import OpAux   : OPERATORS_AUX   Op)
       (Import Clks    : CLOCKS          Ids)
       (Import ExprSyn : NLEXPRSYNTAX        Op)
       (Import Syn     : NLSYNTAX        Ids Op       Clks ExprSyn)
       (Import Str     : STREAM              Op OpAux)
       (Import Ord     : ORDERED         Ids Op       Clks ExprSyn Syn)
       (Import ExprSem : NLEXPRSEMANTICS Ids Op OpAux Clks ExprSyn     Str)
       (Import Sem     : NLSEMANTICS     Ids Op OpAux Clks ExprSyn Syn Str Ord ExprSem)
       (Import Interp  : NLINTERPRETOR   Ids Op OpAux Clks ExprSyn     Str     ExprSem)
       (Import Mem     : MEMORIES        Ids Op       Clks ExprSyn Syn)
       (Import IsD     : ISDEFINED       Ids Op       Clks ExprSyn Syn                 Mem)
       (Import IsV     : ISVARIABLE      Ids Op       Clks ExprSyn Syn                 Mem IsD)
       (Import IsF     : ISFREE          Ids Op       Clks ExprSyn Syn)
       (Import NoD     : NODUP           Ids Op       Clks ExprSyn Syn                 Mem IsD IsV).

  Definition memories := stream (memory val).
  Definition history := stream env.

  Definition mfby (x: ident) (c0: val) (xs: stream value) (rs: stream bool) (M M': memories) (ys: stream value) : Prop :=
    find_val x (M 0) = Some c0
    /\ (forall n, find_val x (M (S n)) = find_val x (M' n))
    /\ forall n, match find_val x (M n) with
           | Some mv =>
             match xs n with
             | absent =>
               find_val x (M' n) = Some mv
               /\ ys n = absent
             | present v =>
               find_val x (M' n) = Some v
               /\ ys n = present (if rs n then c0 else mv)
             end
           | None => False
           end.

  Definition or_str (b b': stream bool) : stream bool :=
    fun n => b n || b' n.

  Section NodeSemantics.

    Definition sub_inst_n (x: ident) (M M': memories) : Prop :=
      forall n, sub_inst x (M n) (M' n).

    Variable G: global.

    Definition memory_closed (M: memory val) (eqs: list equation) : Prop :=
      (forall i, find_inst i M <> None -> InMembers i (gather_insts eqs))
      /\ forall x, find_val x M <> None -> In x (gather_mems eqs).

    Definition memory_closed_n (M: memories) (eqs: list equation) : Prop :=
      forall n, memory_closed (M n) eqs.

    Inductive msem_equation: stream bool -> stream bool -> history -> memories -> memories -> equation -> Prop :=
    | SEqDef:
        forall bk rs H M M' x ck xs ce,
          (forall n, sem_var_instant (H n) x (xs n)) ->
          (forall n, sem_caexp_instant (bk n) (H n) ck ce (xs n)) ->
          msem_equation bk rs H M M' (EqDef x ck ce)
    | SEqApp:
        forall bk rs H M M' x xs ck f Mx Mx' arg ls xss,
          hd_error xs = Some x ->
          sub_inst_n x M Mx ->
          sub_inst_n x M' Mx' ->
          (forall n, sem_laexps_instant (bk n) (H n) ck arg (ls n)) ->
          (forall n, sem_vars_instant (H n) xs (xss  n))->
          msem_node f rs ls Mx Mx' xss ->
          msem_equation bk rs H M M' (EqApp xs ck f arg None)
    | SEqReset:
        forall bk rs' H M M' x xs ck f Mx Mx' arg y ys rs ls xss,
          hd_error xs = Some x ->
          sub_inst_n x M Mx ->
          sub_inst_n x M' Mx' ->
          (forall n, sem_laexps_instant (bk n) (H n) ck arg (ls n)) ->
          (forall n, sem_vars_instant (H n) xs (xss n)) ->
          (forall n, sem_var_instant (H n) y (ys n)) ->
          reset_of ys rs ->
          msem_node f (or_str rs rs') ls Mx Mx' xss ->
          msem_equation bk rs' H M M' (EqApp xs ck f arg (Some y))
    | SEqFby:
        forall bk rs H M M' x ck ls xs c0 le,
          (forall n, sem_laexp_instant (bk n) (H n) ck le (ls n)) ->
          (forall n, sem_var_instant (H n) x (xs n)) ->
          mfby x (sem_const c0) ls rs M M' xs ->
          msem_equation bk rs H M M' (EqFby x ck c0 le)

    with msem_node:
           ident -> stream bool -> stream (list value) -> memories -> memories -> stream (list value) -> Prop :=
           SNode:
             forall bk rs H f xss M M' yss node,
               clock_of xss bk ->
               find_node f G = Some node ->
               (forall n, sem_vars_instant (H n) (map fst node.(n_in)) (xss n)) ->
               (forall n, sem_vars_instant (H n) (map fst node.(n_out)) (yss n)) ->
               same_clock xss ->
               same_clock yss ->
               (forall n, absent_list (xss n) <-> absent_list (yss n)) ->
               (forall n, sem_clocked_vars_instant (bk n) (H n) (idck node.(n_in))) ->
               Forall (msem_equation bk rs H M M') node.(n_eqs) ->
               memory_closed_n M node.(n_eqs) ->
               memory_closed_n M' node.(n_eqs) ->
               msem_node f rs xss M M' yss.

  End NodeSemantics.

  (** ** Induction principle for [msem_equation] and [msem_node] *)

  (** The automagically-generated induction principle is not strong
enough: it does not support the internal fixpoint introduced by
[Forall] *)

  Section msem_node_mult.

    Variable G: global.

    Variable P_equation: stream bool -> stream bool -> history -> memories -> memories -> equation -> Prop.
    Variable P_node: ident -> stream bool -> stream (list value) -> memories -> memories -> stream (list value) -> Prop.

    Hypothesis EqDefCase:
      forall bk rs H M M' x ck xs ce,
        (forall n, sem_var_instant (H n) x (xs n)) ->
        (forall n, sem_caexp_instant (bk n) (H n) ck ce (xs n)) ->
        P_equation bk rs H M M' (EqDef x ck ce).

    Hypothesis EqAppCase:
      forall bk rs H M M' x xs ck f Mx Mx' arg ls xss,
        hd_error xs = Some x ->
        sub_inst_n x M Mx ->
        sub_inst_n x M' Mx' ->
        (forall n, sem_laexps_instant (bk n) (H n) ck arg (ls n)) ->
        (forall n, sem_vars_instant (H n) xs (xss  n))->
        msem_node G f rs ls Mx Mx' xss ->
        P_node f rs ls Mx Mx' xss ->
        P_equation bk rs H M M' (EqApp xs ck f arg None).

    Hypothesis EqResetCase:
      forall bk rs' H M M' x xs ck f Mx Mx' arg y ys rs ls xss,
        hd_error xs = Some x ->
        sub_inst_n x M Mx ->
        sub_inst_n x M' Mx' ->
        (forall n, sem_laexps_instant (bk n) (H n) ck arg (ls n)) ->
        (forall n, sem_vars_instant (H n) xs (xss n)) ->
        (forall n, sem_var_instant (H n) y (ys n)) ->
        reset_of ys rs ->
        msem_node G f (or_str rs rs') ls Mx Mx' xss ->
        P_node f (or_str rs rs') ls Mx Mx' xss ->
        P_equation bk rs' H M M' (EqApp xs ck f arg (Some y)).

    Hypothesis EqFbyCase:
      forall bk rs H M M' x ck ls xs c0 le,
        (forall n, sem_laexp_instant (bk n) (H n) ck le (ls n)) ->
        (forall n, sem_var_instant (H n) x (xs n)) ->
        mfby x (sem_const c0) ls rs M M' xs ->
        P_equation bk rs H M M' (EqFby x ck c0 le).

    Hypothesis NodeCase:
      forall bk rs H f xss M M' yss node,
        clock_of xss bk ->
        find_node f G = Some node ->
        (forall n, sem_vars_instant (H n) (map fst node.(n_in)) (xss n)) ->
        (forall n, sem_vars_instant (H n) (map fst node.(n_out)) (yss n)) ->
        same_clock xss ->
        same_clock yss ->
        (forall n, absent_list (xss n) <-> absent_list (yss n)) ->
        (forall n, sem_clocked_vars_instant (bk n) (H n) (idck node.(n_in))) ->
        Forall (msem_equation G bk rs H M M') node.(n_eqs) ->
        memory_closed_n M node.(n_eqs) ->
        memory_closed_n M' node.(n_eqs) ->
        Forall (P_equation bk rs H M M') node.(n_eqs) ->
        P_node f rs xss M M' yss.

    Fixpoint msem_equation_mult
             (b rs: stream bool) (H: history) (M M': memories) (e: equation)
             (Sem: msem_equation G b rs H M M' e) {struct Sem}
      : P_equation b rs H M M' e
    with msem_node_mult
           (f: ident)
           (rs: stream bool)
           (xss: stream (list value))
           (M M': memories)
           (oss: stream (list value))
           (Sem: msem_node G f rs xss M M' oss) {struct Sem}
         : P_node f rs xss M M' oss.
    Proof.
      - destruct Sem; eauto.
      - destruct Sem; eauto.
        eapply NodeCase; eauto.
        match goal with
          H: memory_closed_n M _, H': memory_closed_n M' _, Heqs: Forall _ (n_eqs _)
          |- _ => clear H H'; induction Heqs; auto
        end.
    Qed.

    Combined Scheme msem_node_equation_reset_ind from
             msem_node_mult, msem_equation_mult.

  End msem_node_mult.

  Definition msem_nodes (G: global) : Prop :=
    Forall (fun no => exists rs xs M M' ys, msem_node G no.(n_name) rs xs M M' ys) G.


  Require Import Setoid.

  Add Parametric Morphism G: (msem_equation G)
      with signature eq_str ==> eq ==> eq ==> eq_str ==> eq_str ==> eq ==> Basics.impl
        as msem_equation_eq_str.
  Proof.
    intros b b' Eb r H M M1 EM M' M1' EM' eq ** Sem.
    inversion_clear Sem.
    - econstructor; eauto.
      intro; now rewrite <-Eb.
    - econstructor; eauto.
      + intro; now rewrite <-EM.
      + intro; now rewrite <-EM'.
      + intro; now rewrite <-Eb.
    - econstructor; eauto.
      + intro; now rewrite <-EM.
      + intro; now rewrite <-EM'.
      + intro; now rewrite <-Eb.
    - econstructor; eauto.
      + intro; rewrite <-Eb; auto.
      + destruct H3 as (?&?& Spec); split; intuition.
        * now rewrite <-EM.
        * now rewrite <-EM, <-EM'.
        * rewrite <-EM, <-EM'; apply Spec.
  Qed.

  Add Parametric Morphism G r H eqs: (fun bk M M' => Forall (msem_equation G bk r H M M') eqs)
      with signature eq_str ==> eq_str ==> eq_str ==> Basics.impl
        as msem_equations_eq_str.
  Proof.
    intros b b' Eb M M1 EM M' M1' EM' ** Sem.
    apply Forall_forall; intros ** Hin; eapply Forall_forall in Sem; eauto.
    rewrite <-Eb, <-EM, <-EM'; auto.
  Qed.

  Add Parametric Morphism G f r: (msem_node G f r)
      with signature eq_str ==> eq_str ==> eq_str ==> eq_str ==> Basics.impl
        as msem_node_eq_str.
  Proof.
    intros xs xs' Exs M M1 EM M' M1' EM' ys ys' Eys Node.
    inv Node.
    econstructor; eauto; intros; try rewrite <-Exs; try rewrite <-Eys; eauto.
    - eapply msem_equations_eq_str; eauto.
      reflexivity.
    - intro; now rewrite <-EM.
    - intro; now rewrite <-EM'.
  Qed.

  Add Parametric Morphism : (or_str)
      with signature eq_str ==> eq_str ==> eq_str
        as or_str_eq_str.
  Proof.
    unfold or_str; intros ** n; congruence.
  Qed.

  Add Parametric Morphism G f: (msem_node G f)
      with signature eq_str ==> eq ==> eq ==> eq ==> eq ==> Basics.impl
        as msem_node_eq_str_rst.
  Proof.
    intros r r' Er ** Node.
    revert dependent r'.
    induction Node as [| | |????????????? Fby|????????????????? Heqs ?? IHeqs]
                     using msem_node_mult
      with (P_equation := fun bk r H M M' eq =>
                            forall r',
                              r ≈ r' ->
                              msem_equation G bk r' H M M' eq);
      intros ** Er; eauto using msem_equation.
    - econstructor; eauto.
      apply IHNode; rewrite Er; reflexivity.
    - destruct Fby as (?&?& Spec); econstructor; eauto; split; intuition; eauto.
      rewrite <-Er; apply Spec.
    - econstructor; eauto.
      apply Forall_forall; intros.
      eapply Forall_forall in IHeqs; eauto.
  Qed.


  (** ** Properties *)

  (** *** Environment cons-ing lemmas *)

  (* Instead of repeating all these cons lemmas (i.e., copying and pasting them),
   and dealing with similar obligations multiple times in translation_correct,
   maybe it would be better to bake Ordered_nodes into msem_node and to make
   it like Miniimp, i.e.,
      find_node f G = Some (nd, G') and msem_node G' nd xs ys ?
   TODO: try this when the other elements are stabilised. *)

  Lemma msem_node_cons:
    forall n G f rs xs M M' ys,
      Ordered_nodes (n :: G) ->
      msem_node (n :: G) f rs xs M M' ys ->
      n.(n_name) <> f ->
      msem_node G f rs xs M M' ys.
  Proof.
    Hint Constructors msem_node msem_equation.
    intros ** Hord Hsem Hnf.
    revert Hnf.
    induction Hsem as [| | | |?????????? Hf ????????? IH]
        using msem_node_mult
      with (P_equation := fun bk rs H M M' eq =>
                            ~Is_node_in_eq n.(n_name) eq ->
                            msem_equation G bk rs H M M' eq); eauto.
    - intro Hnin.
      econstructor; eauto.
      apply IHHsem. intro Hnf; apply Hnin; rewrite Hnf. constructor.
    - intro Hnin.
      econstructor; eauto.
      apply IHHsem. intro Hnf; apply Hnin; rewrite Hnf. constructor.
    - intro.
      pose proof Hf.
      rewrite find_node_tl with (1:=Hnf) in Hf.
      econstructor; eauto.
      apply find_node_later_not_Is_node_in with (2:=Hf) in Hord.
      apply Is_node_in_Forall in Hord.
      apply Forall_Forall with (1:=Hord) in IH.
      apply Forall_impl with (2:=IH).
      intuition.
  Qed.

  Lemma msem_node_cons2:
    forall n G f rs xs M M' ys,
      Ordered_nodes G ->
      msem_node G f rs xs M M' ys ->
      Forall (fun n' => n_name n <> n_name n') G ->
      msem_node (n :: G) f rs xs M M' ys.
  Proof.
    Hint Constructors msem_equation.
    intros ** Hord Hsem Hnin.
    assert (Hnin':=Hnin).
    revert Hnin'.
    induction Hsem as [| | | |???????? n' ? Hfind ?????? Heqs WF WF' IH]
        using msem_node_mult
      with (P_equation := fun bk rs H M M' eq =>
                            ~Is_node_in_eq n.(n_name) eq ->
                            msem_equation (n :: G) bk rs H M M' eq); eauto.
    intro HH; clear HH.
    assert (n.(n_name) <> f) as Hnf.
    { intro Hnf.
      rewrite Hnf in *.
      pose proof (find_node_name _ _ _ Hfind).
      apply find_node_split in Hfind.
      destruct Hfind as [bG [aG Hge]].
      rewrite Hge in Hnin.
      apply Forall_app in Hnin.
      destruct Hnin as [H' Hfg]; clear H'.
      inversion_clear Hfg.
      match goal with H:f<>_ |- False => now apply H end.
    }
    apply find_node_other with (2:=Hfind) in Hnf.
    econstructor; eauto.
    + assert (forall g, Is_node_in g n'.(n_eqs) -> Exists (fun nd=> g = nd.(n_name)) G)
        as Hniex by (intros g Hini;
                     apply find_node_find_again with (1:=Hord) (2:=Hfind) in Hini;
                     exact Hini).
      assert (Forall (fun eq => forall g,
                          Is_node_in_eq g eq -> Exists (fun nd=> g = nd.(n_name)) G)
                     n'.(n_eqs)) as HH.
      {
        clear Heqs IH WF WF'.
        induction n'.(n_eqs) as [|eq eqs]; [now constructor|].
        constructor.
        - intros g Hini.
          apply Hniex.
          constructor 1; apply Hini.
        - apply IHeqs.
          intros g Hini; apply Hniex.
          constructor 2; apply Hini.
      }
      apply Forall_Forall with (1:=HH) in IH.
      apply Forall_impl with (2:=IH).
      intros eq (Hsem & IH1).
      apply IH1.
      intro Hini.
      apply Hsem in Hini.
      apply Forall_Exists with (1:=Hnin) in Hini.
      apply Exists_exists in Hini.
      destruct Hini as [nd' [Hin [Hneq Heq]]].
      intuition.
  Qed.

  Lemma msem_equations_cons:
    forall G bk rs H M M' eqs n,
      Ordered_nodes (n :: G) ->
      ~Is_node_in n.(n_name) eqs ->
      (Forall (msem_equation G bk rs H M M') eqs <->
       Forall (msem_equation (n :: G) bk rs H M M') eqs).
  Proof.
    intros ** Hord Hnini.
    induction eqs as [|eq eqs IH]; [now constructor|].
    apply not_Is_node_in_cons in Hnini as [Hnini Hninis].
    split; intros Hsem; apply Forall_cons2 in Hsem as [Heq Heqs];
      apply IH in Heqs; auto; constructor; auto.
    - inv Hord.
      destruct Heq; eauto using msem_node_cons2.
    - inv Heq; eauto;
        assert (n.(n_name) <> f)
        by (intro HH; apply Hnini; rewrite HH; constructor);
        eauto using msem_node_cons.
  Qed.

  Lemma find_node_msem_node:
    forall G f,
      msem_nodes G ->
      find_node f G <> None ->
      exists rs xs M M' ys,
        msem_node G f rs xs M M' ys.
  Proof.
    intros G f Hnds Hfind.
    apply find_node_Exists in Hfind.
    apply Exists_exists in Hfind.
    destruct Hfind as [nd [Hin Hf]].
    unfold msem_nodes in Hnds.
    rewrite Forall_forall in Hnds.
    apply Hnds in Hin.
    destruct Hin as (rs & xs & M & M' & ys &?).
    exists rs, xs, M, M', ys.
    rewrite Hf in *; auto.
  Qed.

  (** *** Memory management *)

  Definition add_val_n (y: ident) (ms: stream val) (M: memories): memories :=
    fun n => add_val y (ms n) (M n).

  Lemma mfby_add_val_n:
    forall x v0 rs ls M M' xs y ms ms',
      x <> y ->
      mfby x v0 rs ls M M' xs ->
      mfby x v0 rs ls (add_val_n y ms M) (add_val_n y ms' M') xs.
  Proof.
    unfold add_val_n.
    intros ** Fby; destruct Fby as (?&?& Spec).
    split; intuition.
    - rewrite find_val_gso; auto.
    - rewrite 2 find_val_gso; auto.
    - rewrite 2 find_val_gso; auto; apply Spec.
  Qed.

  Definition add_inst_n (y: ident) (M' M: memories): memories :=
    fun n => add_inst y (M' n) (M n).

  Lemma mfby_add_inst_n:
    forall x v0 rs ls M M' xs y My My',
      mfby x v0 rs ls M M' xs ->
      mfby x v0 rs ls (add_inst_n y My M) (add_inst_n y My' M') xs.
  Proof.
    inversion 1; econstructor; eauto.
  Qed.

  Hint Resolve mfby_add_val_n mfby_add_inst_n.

  Lemma msem_equation_madd_val:
    forall G bk rs H M M' x ms ms' eqs,
      ~Is_defined_in_eqs x eqs ->
      Forall (msem_equation G bk rs H M M') eqs ->
      Forall (msem_equation G bk rs H (add_val_n x ms M) (add_val_n x ms' M')) eqs.
  Proof.
    Hint Constructors msem_equation.
    intros ** Hnd Hsem.
    induction eqs as [|eq eqs IH]; [now constructor|].
    apply not_Is_defined_in_cons in Hnd.
    destruct Hnd as [Hnd Hnds].
    apply Forall_cons2 in Hsem.
    destruct Hsem as [Hsem Hsems].
    constructor; [|now apply IH with (1:=Hnds) (2:=Hsems)].
    destruct Hsem; eauto.
    apply not_Is_defined_in_eq_EqFby in Hnd.
    eapply SEqFby; eauto.
  Qed.

  Lemma msem_equation_madd_inst:
    forall G bk rs H M M' Mx Mx' x eqs,
      ~Is_defined_in_eqs x eqs ->
      Forall (msem_equation G bk rs H M M') eqs ->
      Forall (msem_equation G bk rs H (add_inst_n x Mx M) (add_inst_n x Mx' M')) eqs.
  Proof.
    Hint Constructors msem_equation.
    intros * Hnd Hsem.
    induction eqs as [|eq eqs IH]; [now constructor|].
    apply not_Is_defined_in_cons in Hnd.
    destruct Hnd as [Hnd Hnds].
    apply Forall_cons2 in Hsem.
    destruct Hsem as [Hsem Hsems].
    constructor; [|now apply IH with (1:=Hnds) (2:=Hsems)].
    destruct Hsem as [|????? x' ???????? Hsome
                         |????? x' ??????????? Hsome|];
      eauto;
      assert (sub_inst_n x' (add_inst_n x Mx M) Mx0)
        by (apply not_Is_defined_in_eq_EqApp in Hnd;
            unfold sub_inst_n, sub_inst, add_inst_n in *; intro;
            rewrite find_inst_gso; auto; intro; subst x; destruct xs;
            inv Hsome; apply Hnd; now constructor);
      assert (sub_inst_n x' (add_inst_n x Mx' M') Mx'0)
        by (apply not_Is_defined_in_eq_EqApp in Hnd;
            unfold sub_inst_n, sub_inst, add_inst_n in *; intro;
            rewrite find_inst_gso; auto; intro; subst x; destruct xs;
            inv Hsome; apply Hnd; now constructor);
      eauto.
  Qed.


  (* XXX: I believe that this comment is outdated ([no_dup_defs] is long gone)

   - The no_dup_defs hypothesis is essential for the EqApp case.

     If the set of equations contains two EqApp's to the same variable:
        eq::eqs = [ EqApp x f lae; ...; EqApp x g lae' ]

     Then it is possible to have a coherent H, namely if
        f(lae) = g(lae')

     But nothing forces the 'memory streams' (internal memories) of
     f(lae) and g(lae') to be the same. This is problematic since they are
     both 'stored' at M x...

   - The no_dup_defs hypothesis is not essential for the EqFby case.

     If the set of equations contains two EqFby's to for the same variable:
        eq::eqs = [ EqFby x v0 lae; ...; EqFby x v0' lae'; ... ]

     then the 'memory streams' associated with each, ms and ms', must be
     identical since if (Forall (sem_equation G H) (eq::eqs)) exists then
     then the H forces the coherence between 'both' x's, and necessarily also
     between v0 and v0', and lae and lae'.

     That said, proving this result is harder than just assuming something
     that should be true anyway: that there are no duplicate definitions in
     eqs.

   Note that the no_dup_defs hypothesis requires a stronger definition of
   either Is_well_sch or Welldef_global.
   *)


  (** ** Fundamental theorem *)

  (**

We show that the standard semantics implies the existence of a
dataflow memory for which the non-standard semantics holds true.

   *)

  Lemma memory_closed_n_App:
    forall M eqs i Mx xs ck f es r,
      memory_closed_n M eqs ->
      hd_error xs = Some i ->
      memory_closed_n (add_inst_n i Mx M) (EqApp xs ck f es r :: eqs).
  Proof.
    intros ** WF Hd n; specialize (WF n); destruct WF as (Insts &?).
    split; auto.
    intro y; intros ** Hin.
    unfold sub_inst, add_inst_n in Hin; apply not_None_is_Some in Hin as (?& Find).
    destruct (ident_eq_dec y i).
    - subst.
      unfold gather_insts, concatMap; simpl.
      destruct xs; simpl in *; inv Hd; left; auto.
    - rewrite find_inst_gso in Find; auto.
      unfold gather_insts, concatMap; simpl.
      apply InMembers_app; right; auto.
      apply Insts; eauto.
      apply not_None_is_Some; eauto.
  Qed.

  Lemma memory_closed_n_Fby:
    forall M eqs x ck v0 e vs,
      memory_closed_n M eqs ->
      memory_closed_n (add_val_n x vs M) (EqFby x ck v0 e :: eqs).
  Proof.
    intros ** WF n; specialize (WF n); destruct WF as (?& Vals).
    split; auto.
    intro y; intros ** Hin.
    unfold add_val_n in Hin; apply not_None_is_Some in Hin as (?& Find).
    destruct (ident_eq_dec y x).
    - subst; simpl; auto.
    - rewrite find_val_gso in Find; auto.
      unfold gather_mems, concatMap; simpl.
      right; apply Vals; eauto.
      apply not_None_is_Some; eauto.
  Qed.


  Lemma sem_msem_eq:
    forall G bk H eqs M M' eq,
      (forall f xs ys,
          sem_node G f xs ys ->
          exists M M', msem_node G f (fun n => false) xs M M' ys) ->
      (forall f r xs ys,
          sem_reset G f r xs ys ->
          exists M M', msem_node G f r xs M M' ys) ->
      sem_equation G bk H eq ->
      NoDup_defs (eq :: eqs) ->
      Forall (msem_equation G bk (fun n => false) (restr_hist H) M M') eqs ->
      memory_closed_n M eqs ->
      memory_closed_n M' eqs ->
      exists M1 M1', Forall (msem_equation G bk (fun n => false) (restr_hist H) M1 M1') (eq :: eqs)
                /\ memory_closed_n M1 (eq :: eqs)
                /\ memory_closed_n M1' (eq :: eqs).
  Proof.
    intros ** IH IH' Heq NoDup Hmeqs WF WF'.
    inversion Heq as [|???????? Hls Hxs Hsem
                         |??????????? Hls Hxs Hy Hr Hsem
                         |???????? Hle Hvar Hfby];
      match goal with H:_=eq |- _ => rewrite <-H in * end.

    - exists M, M'.
      econstructor; eauto.

    - apply IH in Hsem as (Mx & Mx' & Hmsem).
      exists (add_inst_n (hd Ids.default x) Mx M), (add_inst_n (hd Ids.default x) Mx' M').

      assert (exists i, hd_error x = Some i) as [i Hsome].
      { assert (Hlen: 0 < length x).
        { assert (length x = length (xs 0))
            by (specialize (Hxs 0); simpl in Hxs; eapply Forall2_length; eauto).

          assert (exists n, length (map fst n.(n_out)) = length (xs 0)
                       /\ 0 < length n.(n_out)) as (n & ? & ?).
          { inv Hmsem.
            exists node0; split; auto.
            - eapply Forall2_length; eauto.
              specialize (H9 0); eauto.
            - exact node0.(n_outgt0).
          }
          assert (length (map fst n.(n_out)) = length n.(n_out))
            by apply map_length.
          intuition.
        }
        now apply length_hd_error.
      }
      erewrite hd_error_Some_hd; eauto; split.
      + constructor.
        * econstructor; eauto;
            unfold sub_inst, add_inst_n; intro; now apply find_inst_gss.
        * inv NoDup.
          apply hd_error_Some_In in Hsome.
          apply msem_equation_madd_inst; auto.
      + split; apply memory_closed_n_App; auto.

    - pose proof Hsem as Hsem'.
      apply IH' in Hsem as (Mx & Mx' & Hmsem).
      exists (add_inst_n (hd Ids.default x) Mx M), (add_inst_n (hd Ids.default x) Mx' M').

      assert (exists i, hd_error x = Some i) as [i Hsome].
      { assert (Hlen: 0 < length x).
        { assert (length x = length (xs 0))
            by (specialize (Hxs 0); simpl in Hxs; eapply Forall2_length; eauto).

          assert (exists n, length (map fst n.(n_out)) = length (xs 0)
                       /\ 0 < length n.(n_out)) as (n & ? & ?).
          { inv Hmsem.
            exists node0; split; auto.
            - eapply Forall2_length; eauto.
              specialize (H9 0); eauto.
            - exact node0.(n_outgt0).
          }
          assert (length (map fst n.(n_out)) = length n.(n_out))
            by apply map_length.
          intuition.
        }
        now apply length_hd_error.
      }
      erewrite hd_error_Some_hd; eauto; split.
      + constructor.
        * econstructor; eauto;
            try (unfold sub_inst, add_inst_n; intro; now apply find_inst_gss).
          eapply msem_node_eq_str_rst; eauto.
          unfold or_str; intro; rewrite Bool.orb_false_r; auto.
        * inv NoDup.
          apply hd_error_Some_In in Hsome.
          apply msem_equation_madd_inst; auto.
      + split; apply memory_closed_n_App; auto.

    - exists (add_val_n x (hold (sem_const c0) ls) M), (add_val_n x (fun n =>
                                                                  match ls n with
                                                                  | present v => v
                                                                  | absent => hold (sem_const c0) ls n
                                                                  end) M');
        split.
      + constructor.
        * unfold add_val_n.
          econstructor; eauto; split; intuition;
             intros; try rewrite Hfby; unfold fby;
               simpl; repeat rewrite find_val_gss; auto.
          destruct (ls n); auto.
        * inv NoDup.
          apply msem_equation_madd_val; eauto.
      + split; apply memory_closed_n_Fby; auto.
  Qed.

  Lemma memory_closed_empty':
    memory_closed_n (fun _ : nat => empty_memory val) [].
  Proof.
    constructor; simpl.
    - setoid_rewrite find_inst_gempty; congruence.
    - setoid_rewrite find_val_gempty; congruence.
  Qed.

  (* XXX: for this lemma, and the ones before/after it, factorize 'G',
'bk' and possibly other variables in a Section *)
  Corollary sem_msem_eqs:
    forall G bk H eqs,
      (forall f xs ys,
          sem_node G f xs ys ->
          exists M M', msem_node G f (fun n => false) xs M M' ys) ->
      (forall f r xs ys,
          sem_reset G f r xs ys ->
          exists M M', msem_node G f r xs M M' ys) ->
      NoDup_defs eqs ->
      Forall (sem_equation G bk H) eqs ->
      exists M1 M1', Forall (msem_equation G bk (fun n => false) (restr_hist H) M1 M1') eqs
                /\ memory_closed_n M1 eqs
                /\ memory_closed_n M1' eqs.
  Proof.
    intros ** IH NoDup Heqs.
    induction eqs as [|eq eqs IHeqs].
    - exists (fun n => empty_memory _), (fun n => empty_memory _); split; auto.
      split; apply memory_closed_empty'.
    - apply Forall_cons2 in Heqs as [Heq Heqs].
      eapply IHeqs in Heqs as (?&?&?&?&?).
      + eapply sem_msem_eq; eauto.
      + eapply NoDup_defs_cons; eauto.
  Qed.


  (* Check functional_choice. *)

  (* Lemma functional_choice_sig: *)
  (*   forall A B (R: A -> B -> Prop), *)
  (*     (forall x, { y | R x y }) -> *)
  (*     exists f, forall x, R x (f x). *)
  (* Proof. *)
  (*   intros ** Ex. *)
  (*   exists (fun n => proj1_sig (Ex n)). *)
  (*   intro x; destruct (Ex x); auto. *)
  (* Qed. *)


  (* Ltac interp_sound n := *)
  (*   repeat match goal with *)
  (*          | H: forall n, sem_var_instant ?H' ?x ?vs |- _ => *)
  (*            specialize (H n); apply sem_var_instant_reset in H *)
  (*          | H: sem_vars ?H' ?xs ?vss |- _ => *)
  (*            specialize (H n); apply sem_vars_instant_reset in H *)
  (*          | H: sem_caexp ?bk ?H' ?c ?e ?vs |- _ => *)
  (*            specialize (H n); simpl in H; eapply sem_caexp_instant_reset in H; eauto *)
  (*          | H: sem_laexp ?bk ?H' ?c ?e ?vs |- _ => *)
  (*            specialize (H n); simpl in H; eapply sem_laexp_instant_reset in H; eauto *)
  (*          | H: sem_laexps ?bk ?H' ?c ?es ?vss |- _ => *)
  (*            specialize (H n); simpl in H; eapply sem_laexps_instant_reset in H; eauto *)
  (*          end; *)
  (*   unfold interp_var, interp_vars, interp_laexp, interp_laexps, interp_caexp, lift, lift'; *)
  (*   try erewrite <-interp_caexp_instant_sound; *)
  (*   try erewrite <-interp_laexp_instant_sound; *)
  (*   try erewrite <-interp_laexps_instant_sound; *)
  (*   try erewrite <-interp_var_instant_sound; *)
  (*   try erewrite <-interp_vars_instant_sound; *)
  (*   eauto. *)

  Lemma memory_closed_empty:
    forall M, memory_closed M [] -> M ≋ empty_memory _.
  Proof.
    intros ** (Insts & Vals); unfold find_val, find_inst in *.
    constructor; simpl in *.
    - intro x.
      assert (Env.find x (values M) = None) as ->.
      { apply not_Some_is_None; intros ** E.
        eapply Vals, not_None_is_Some; eauto.
      }
      now rewrite Env.gempty.
    - split.
      + setoid_rewrite Env.Props.P.F.empty_in_iff; setoid_rewrite Env.In_find; split; try contradiction.
        intros (?&?); eapply Insts, not_None_is_Some; eauto.
      + setoid_rewrite Env.Props.P.F.empty_mapsto_iff; contradiction.
  Qed.

  Definition remove_inst_n (x: ident) (M: memories) : memories :=
    fun n => remove_inst x (M n).

  Definition remove_val_n (x: ident) (M: memories) : memories :=
    fun n => remove_val x (M n).

  Lemma msem_equation_remove_inst:
    forall G bk rs eqs H M M' x,
      ~Is_defined_in_eqs x eqs ->
      Forall (msem_equation G bk rs H M M') eqs ->
      Forall (msem_equation G bk rs H (remove_inst_n x M) (remove_inst_n x M')) eqs.
  Proof.
    Ltac foo H := unfold sub_inst_n, sub_inst in *; intro n;
                setoid_rewrite find_inst_gro; auto;
                intro E; subst; apply H;
                constructor;
                apply hd_error_Some_In; auto.
    induction eqs as [|[]]; intros ** Hnotin Sems;
      inversion_clear Sems as [|?? Sem]; auto; inversion_clear Sem;
        apply not_Is_defined_in_cons in Hnotin as (Hnotin &?);
        constructor; eauto using msem_equation;
          econstructor; eauto; foo Hnotin.
  Qed.

  Lemma msem_equation_remove_val:
    forall G bk rs eqs H M M' x,
      ~Is_defined_in_eqs x eqs ->
      Forall (msem_equation G bk rs H M M') eqs ->
      Forall (msem_equation G bk rs H (remove_val_n x M) (remove_val_n x M')) eqs.
  Proof.
    induction eqs as [|[]]; intros ** Hnotin Sems;
      inversion_clear Sems as [|?? Sem]; auto;
        inversion_clear Sem as [| | |????????????? Mfby];
        apply not_Is_defined_in_cons in Hnotin as (Hnotin &?);
        constructor; eauto using msem_equation.
    assert (x <> i) by (intro E; subst; apply Hnotin; constructor).
    destruct Mfby as (?&?& Spec).
    econstructor; eauto; unfold remove_val_n.
    split; intuition; intros; repeat rewrite find_val_gro; auto.
    apply Spec.
  Qed.

  Lemma memory_closed_n_App':
    forall M eqs i xs ck f es r,
      memory_closed_n M (EqApp xs ck f es r :: eqs) ->
      hd_error xs = Some i ->
      memory_closed_n (remove_inst_n i M) eqs.
  Proof.
    intros ** WF Hd n; specialize (WF n); destruct WF as (Insts &?).
    split; auto.
    intro y; intros ** Hin.
    unfold sub_inst, remove_inst_n in Hin; apply not_None_is_Some in Hin as (?& Find).
    destruct (ident_eq_dec y i).
    - subst; rewrite find_inst_grs in Find; discriminate.
    - rewrite find_inst_gro in Find; auto.
      unfold gather_insts, concatMap in Insts; simpl in Insts.
      destruct xs; simpl in *; inv Hd.
      edestruct Insts.
      + apply not_None_is_Some; eauto.
      + congruence.
      + auto.
  Qed.

  Lemma memory_closed_n_Fby':
    forall M eqs x ck v0 e,
      memory_closed_n M (EqFby x ck v0 e :: eqs) ->
      memory_closed_n (remove_val_n x M) eqs.
  Proof.
    intros ** WF n; specialize (WF n); destruct WF as (?& Vals).
    split; auto.
    intro y; intros ** Hin.
    unfold remove_val_n in Hin; apply not_None_is_Some in Hin as (?& Find).
    destruct (ident_eq_dec y x).
    - subst; rewrite find_val_grs in Find; discriminate.
    - rewrite find_val_gro in Find; auto.
      unfold gather_mems, concatMap in Vals; simpl in Vals.
      edestruct Vals.
      + apply not_None_is_Some; eauto.
      + congruence.
      + auto.
  Qed.

  (** Absent Until *)

  Lemma mfby_absent_until:
    forall n0 x v0 ls rs M M' xs,
      mfby x v0 ls rs M M' xs ->
      (forall n, n < n0 -> ls n = absent) ->
      forall n, n <= n0 -> find_val x (M n) = Some v0.
  Proof.
    intros ** Mfby Abs n E; induction n;
      destruct Mfby as (Init & Loop & Spec); auto.
    rewrite Loop.
    specialize (Spec n).
    destruct (find_val x (M n)); try contradiction.
    rewrite Abs in Spec; try omega.
    destruct Spec as [->].
    apply IHn; omega.
  Qed.

  Lemma msem_eqs_absent_until:
    forall M M' G n0 eqs bk rs H n,
    (forall f r xss M M' yss,
        msem_node G f r xss M M' yss ->
        (forall n, n < n0 -> absent_list (xss n)) ->
        forall n, n <= n0 -> M n ≋ M 0) ->
    Ordered_nodes G ->
    n <= n0 ->
    (forall n, n < n0 -> bk n = false) ->
    NoDup_defs eqs ->
    memory_closed_n M eqs ->
    Forall (msem_equation G bk rs H M M') eqs ->
    M n ≋ M 0.
  Proof.
    intros ** IH Hord Spec Absbk Nodup Closed Heqs.
    revert dependent M; revert dependent M'.
    induction eqs as [|[] ? IHeqs]; intros;
      inversion_clear Heqs as [|?? Sem Sems];
      try inversion_clear Sem as [|?????????????? Hd ?? Args ? Node|
                                  ????????????????? Hd ?? Args ??? Node|
                                  ??????????? Arg ? Mfby];
      inv Nodup; eauto.
    - assert (forall n, M n ≋ empty_memory _) as E
          by (intro; apply memory_closed_empty; auto).
     rewrite 2 E; reflexivity.

    - apply msem_equation_remove_inst with (x := x) in Sems.
      + apply IHeqs in Sems; auto.
        *{ apply IH with (n := n) in Node; auto.
           - erewrite add_remove_inst_same; eauto;
               symmetry; erewrite add_remove_inst_same; eauto.
             now rewrite Sems, Node.
           - intros k ** Spec'; specialize (Args k); simpl in Args.
             rewrite Absbk in Args; auto.
             inversion_clear Args as [?????? SClock|??? ->].
             + contradict SClock; apply not_subrate_clock.
             + apply all_absent_spec.
         }
        * eapply memory_closed_n_App'; eauto.
      + apply hd_error_Some_In in Hd; auto.

    - apply msem_equation_remove_inst with (x := x) in Sems.
      + apply IHeqs in Sems; auto.
        *{ apply IH with (n := n) in Node; auto.
           - erewrite add_remove_inst_same; eauto;
               symmetry; erewrite add_remove_inst_same; eauto.
             now rewrite Sems, Node.
           - intros k ** Spec'; specialize (Args k); simpl in Args.
             rewrite Absbk in Args; auto.
             inversion_clear Args as [?????? SClock|??? ->].
             + contradict SClock; apply not_subrate_clock.
             + apply all_absent_spec.
         }
        * eapply memory_closed_n_App'; eauto.
      + apply hd_error_Some_In in Hd; auto.

    - apply msem_equation_remove_val with (x := i) in Sems; auto.
      apply IHeqs in Sems; auto.
      + assert (find_val i (M n) = Some (sem_const c0)).
        { eapply mfby_absent_until; eauto.
          intros k ** Spec'; specialize (Arg k); simpl in Arg.
          rewrite Absbk in Arg; auto.
          inversion_clear Arg as [???? SClock|]; auto.
          contradict SClock; apply not_subrate_clock.
        }
        destruct Mfby as (Init & Loop & Spec').
        erewrite add_remove_val_same; eauto;
          symmetry; erewrite add_remove_val_same; eauto.
        now rewrite Sems.
      + eapply memory_closed_n_Fby'; eauto.
  Qed.

  Theorem msem_node_absent_until:
    forall n0 G f r xss M M' yss,
      Ordered_nodes G ->
      msem_node G f r xss M M' yss ->
      (forall n, n < n0 -> absent_list (xss n)) ->
      forall n, n <= n0 -> M n ≋ M 0.
  Proof.
    induction G as [|node].
    inversion 2;
      match goal with Hf: find_node _ [] = _ |- _ => inversion Hf end.
    intros ** Hord Hsem Abs n Spec.
    assert (Hsem' := Hsem).
    inversion_clear Hsem' as [????????? Clock Hfind Ins ????? Heqs].
    assert (forall n, n < n0 -> bk n = false) as Absbk.
    { intros k Spec'; apply Abs in Spec'.
      rewrite <-Bool.not_true_iff_false.
      intro E; apply Clock in E.
      specialize (Ins k).
      apply Forall2_length in Ins.
      destruct (xss k).
      - rewrite map_length in Ins; simpl in Ins.
        pose proof (n_ingt0 node0); omega.
      - inv Spec'; inv E;  congruence.
    }
    pose proof (find_node_not_Is_node_in _ _ _ Hord Hfind) as Hnini.
    pose proof Hord; inv Hord.
    pose proof Hfind.
    simpl in Hfind.
    destruct (ident_eqb node.(n_name) f) eqn:Hnf.
    - inv Hfind.
      eapply msem_equations_cons in Heqs; eauto.
      eapply msem_eqs_absent_until; eauto.
      apply NoDup_defs_node.
    - eapply msem_node_cons in Hsem; eauto.
      now apply ident_eqb_neq.
  Qed.

  (** Loop *)

  Lemma msem_eqs_loop:
    forall M M' G eqs bk rs H n,
      (forall f r xss M M' yss n,
          msem_node G f r xss M M' yss ->
          M (S n) ≋ M' n) ->
      Ordered_nodes G ->
      NoDup_defs eqs ->
      memory_closed_n M eqs ->
      memory_closed_n M' eqs ->
      Forall (msem_equation G bk rs H M M') eqs ->
      M (S n) ≋ M' n.
  Proof.
    intros ** IH Hord Nodup Closed Closed' Heqs.
    revert dependent M; revert dependent M'.
    induction eqs as [|[] ? IHeqs]; intros;
      inversion_clear Heqs as [|?? Sem Sems];
      try inversion_clear Sem as [|
                                  ?????????????? Hd ?? Args ? Node|
                                  ????????????????? Hd ?? Args ??? Node|
                                  ??????????? Arg ? Mfby];
      inv Nodup; eauto.
    - assert (forall n, M n ≋ empty_memory _) as E
          by (intro; apply memory_closed_empty; auto).
      assert (forall n, M' n ≋ empty_memory _) as E'
          by (intro; apply memory_closed_empty; auto).
      rewrite E, E'; reflexivity.

    - apply msem_equation_remove_inst with (x := x) in Sems.
      + apply IHeqs in Sems; try eapply memory_closed_n_App'; eauto.
        apply IH with (n := n) in Node; auto.
        erewrite add_remove_inst_same; eauto;
          symmetry; erewrite add_remove_inst_same; eauto.
        now rewrite Sems, Node.
      + apply hd_error_Some_In in Hd; auto.

    - apply msem_equation_remove_inst with (x := x) in Sems.
      + apply IHeqs in Sems; try eapply memory_closed_n_App'; eauto.
        apply IH with (n := n) in Node; auto.
        erewrite add_remove_inst_same; eauto;
          symmetry; erewrite add_remove_inst_same; eauto.
        now rewrite Sems, Node.
      + apply hd_error_Some_In in Hd; auto.

    - apply msem_equation_remove_val with (x := i) in Sems; auto.
      apply IHeqs in Sems; try eapply memory_closed_n_Fby'; eauto.
      destruct Mfby as (Init & Loop & Spec').
      specialize (Spec' (S n)).
      destruct (find_val i (M (S n))) eqn: Eq; try contradiction.
      erewrite add_remove_val_same; eauto.
      rewrite Loop in Eq.
      symmetry; erewrite add_remove_val_same; eauto.
      now rewrite Sems.
  Qed.

  Theorem msem_node_loop:
    forall G f r xss M M' yss n,
      Ordered_nodes G ->
      msem_node G f r xss M M' yss ->
      M (S n) ≋ M' n.
  Proof.
    induction G as [|node].
    inversion 2;
      match goal with Hf: find_node _ [] = _ |- _ => inversion Hf end.
    intros ** Hord Hsem.
    assert (Hsem' := Hsem).
    inversion_clear Hsem' as [????????? Clock Hfind Ins ????? Heqs].
    pose proof (find_node_not_Is_node_in _ _ _ Hord Hfind) as Hnini.
    pose proof Hord; inv Hord.
    pose proof Hfind.
    simpl in Hfind.
    destruct (ident_eqb node.(n_name) f) eqn:Hnf.
    - inv Hfind.
      eapply msem_equations_cons in Heqs; eauto.
      eapply msem_eqs_loop; eauto.
      apply NoDup_defs_node.
    - eapply msem_node_cons in Hsem; eauto.
      now apply ident_eqb_neq.
  Qed.

  Lemma msem_nodes_reset_spec:
    forall G f r' r xs ys F F',
      Ordered_nodes G ->
      (forall k,
          msem_node G f (mask false k r r')
                    (mask (all_absent (xs 0)) k r xs)
                    (F k) (F' k)
                    (mask (all_absent (ys 0)) k r ys)) ->
      forall n, r n = true -> F (count r n) n ≋ F (count r n) 0.
  Proof.
    intros ** Nodes n Hr.
    specialize (Nodes (count r n)).
    eapply msem_node_absent_until; eauto.
    intros ** Spec.
    rewrite mask_opaque.
    - apply all_absent_spec.
    - eapply count_positive in Spec; eauto; omega.
  Qed.

  Lemma or_str_comm:
    forall b b',
      or_str b b' ≈ or_str b' b.
  Proof.
    unfold or_str; intros ** n.
    apply Bool.orb_comm.
  Qed.

  Lemma or_str_assoc:
    forall b b' b'',
      or_str b (or_str b' b'') ≈ or_str (or_str b b') b''.
  Proof.
    unfold or_str; intros ** n.
    apply Bool.orb_assoc.
  Qed.

  Lemma mask_or_str:
    forall b b' k r,
      mask false k r (or_str b b') ≈ or_str (mask false k r b) (mask false k r b').
  Proof.
    unfold or_str; intros ** n.
    destruct (NPeano.Nat.eq_dec k (count r n)) eqn: E.
    - rewrite 3 mask_transparent; auto.
    - rewrite 3 mask_opaque; auto.
  Qed.

  Lemma sem_interp_laexps_instant_mask:
    forall ck es ls xs r FH k,
    let bk := fun n : nat => clock_of' (mask (all_absent (xs 0)) (count r n) r xs) n in
    let H := fun n : nat => FH (count r n) n in
    0 < length (xs 0) ->
    (forall n, sem_laexps_instant (clock_of' (mask (all_absent (xs 0)) k r xs) n) (FH k n) ck es (ls n)) ->
    ls ≈ mask (all_absent (interp_laexps_instant (bk 0) (H 0) ck es)) k r
       (fun n => interp_laexps_instant (bk n) (H n) ck es).
  Proof.
    intros ** Length Exps n.
    specialize (Exps n).
    destruct (NPeano.Nat.eq_dec k (count r n)) eqn: E.
    - subst.
      rewrite mask_transparent; auto.
      eapply interp_laexps_instant_sound; auto.
    - rewrite mask_opaque; auto.
      assert (clock_of' (mask (all_absent (xs 0)) k r xs) n = false) as Hbk.
      { unfold clock_of'; rewrite mask_opaque; auto.
        induction (xs 0); simpl in *; auto; omega.
      }
      rewrite Hbk in Exps.
      inversion_clear Exps as [?????? SemCk|??? Eq].
      + contradict SemCk; apply not_subrate_clock.
      + rewrite Eq.
        unfold interp_laexps_instant.
        destruct (forallb (fun v => v ==b absent) (interp_lexps_instant (bk 0) (H 0) es)
                          && negb (interp_clock_instant (bk 0) (H 0) ck)
                  || forallb (fun v => v <>b absent) (interp_lexps_instant (bk 0) (H 0) es)
                            && interp_clock_instant (bk 0) (H 0) ck);
          unfold interp_lexps_instant; rewrite all_absent_map; auto.
        unfold all_absent at 3; rewrite all_absent_map; auto.
  Qed.

  Lemma sem_interp_vars_instant_mask:
    forall xs xss r FH k,
    let H := fun n : nat => FH (count r n) n in
    (forall n, k <> count r n -> absent_list (xss n)) ->
    (forall n, sem_vars_instant (FH k n) xs (xss n)) ->
    xss ≈ mask (all_absent (interp_vars_instant (H 0) xs)) k r (fun n => interp_vars_instant (H n) xs).
  Proof.
    intros ** Abs Vars n.
    specialize (Vars n).
    destruct (NPeano.Nat.eq_dec k (count r n)) eqn: E.
    - subst.
      rewrite mask_transparent; auto.
      induction Vars as [|???? Var]; intros; simpl; auto.
      f_equal; auto.
      unfold interp_var_instant; subst H; simpl.
      rewrite Var; auto.
    - rewrite mask_opaque; auto.
      apply absent_list_spec; auto.
      apply Forall2_length in Vars.
      unfold interp_vars_instant.
      rewrite map_length; auto.
  Qed.

  Lemma sem_interp_var_instant_mask:
    forall x xs r FH k,
      let H := fun n : nat => FH (count r n) n in
      (forall n, k <> count r n -> xs n = absent) ->
      (forall n, sem_var_instant (FH k n) x (xs n)) ->
      xs ≈ mask absent k r (fun n => interp_var_instant (H n) x).
  Proof.
    intros ** Var n.
    specialize (Var n).
    destruct (NPeano.Nat.eq_dec k (count r n)) eqn: E.
    - subst.
      rewrite mask_transparent; auto.
      unfold interp_var_instant; subst H; simpl.
      rewrite Var; auto.
    - rewrite mask_opaque; auto.
  Qed.

  Lemma msem_node_wf:
    forall G f r xss M M' yss,
      msem_node G f r xss M M' yss ->
      wf_streams xss /\ wf_streams yss.
  Proof.
    intros ** Sem; split; inversion_clear Sem as [??????????? Ins Outs].
    - intros k k'; pose proof Ins as Ins'.
      specialize (Ins k); specialize (Ins' k');
        apply Forall2_length in Ins; apply Forall2_length in Ins';
          now rewrite Ins in Ins'.
    - intros k k'; pose proof Outs as Outs'.
      specialize (Outs k); specialize (Outs' k');
        apply Forall2_length in Outs; apply Forall2_length in Outs';
          now rewrite Outs in Outs'.
  Qed.

 Require Import Coq.Logic.ClassicalChoice.
  Require Import Coq.Logic.ConstructiveEpsilon.
  Require Import Coq.Logic.Epsilon.
  Require Import Coq.Logic.IndefiniteDescription.

  Lemma msem_node_slices:
    forall G f r r' xs ys F F',
      Ordered_nodes G ->
      (forall k,
          msem_node G f (mask false k r r')
                    (mask (all_absent (xs 0)) k r xs)
                    (F k) (F' k)
                    (mask (all_absent (ys 0)) k r ys)) ->
      msem_node G f (or_str r r')
                xs
                (fun n => match n with
                       | 0 => F (count r 0) 0
                       | S n => F' (count r n) n
                       end)
                (fun n => F' (count r n) n)
                ys.
  Proof.
    induction G as [|n]; intros ** Ord Sems;
      try (specialize (Sems 0); inversion_clear Sems as [?????????? Find]; now inv Find).
    assert (exists node, find_node f (n :: G) = Some node) as (node & Find)
        by (specialize (Sems 0); inv Sems; eauto).
    pose proof Find as Find'.
    simpl in Find'.
    destruct (ident_eqb (n_name n) f) eqn: E.
    - inv Find'.
      assert (forall k, exists Hk,
                   let bk := clock_of' (mask (all_absent (xs 0)) k r xs) in
                   (forall n, sem_vars_instant (Hk n) (map fst node.(n_in)) (mask (all_absent (xs 0)) k r xs n))
                   /\ (forall n, sem_vars_instant (Hk n) (map fst node.(n_out)) (mask (all_absent (ys 0)) k r ys n))
                   /\ same_clock (mask (all_absent (xs 0)) k r xs)
                   /\ same_clock (mask (all_absent (ys 0)) k r ys)
                   /\ (forall n, absent_list (mask (all_absent (xs 0)) k r xs n)
                           <-> absent_list (mask (all_absent (ys 0)) k r ys n))
                   /\ (forall n, sem_clocked_vars_instant (bk n) (Hk n) (idck node.(n_in)))
                   /\ Forall (msem_equation (node :: G) bk (mask false k r r') Hk (F k) (F' k)) node.(n_eqs)
                   /\ memory_closed_n (F k) node.(n_eqs)
                   /\ memory_closed_n (F' k) node.(n_eqs)) as Node.
      { intro; specialize (Sems k);
          inversion_clear Sems as [????????? Clock Find'];
          rewrite Find' in Find; inv Find; do 2 eexists; intuition; eauto;
            apply clock_of_equiv' in Clock.
        - rewrite <-Clock; auto.
        - eapply msem_equations_eq_str; eauto; reflexivity.
      }
      apply functional_choice in Node as (FH & Node).
      assert (0 < length (xs 0)) as Length.
      { clear - Sems; pose proof Sems as Sems'.
        specialize (Sems 0); inversion_clear Sems as [??????????? Ins]; specialize (Ins 0).
        apply Forall2_length in Ins.
        rewrite mask_length in Ins.
        - rewrite <-Ins, map_length; apply n_ingt0.
        - eapply wf_streams_mask.
          intro k'; specialize (Sems' k').
          eapply msem_node_wf in Sems' as (); eauto.
      }
      (* assert (forall k n, F k (S n) ≋ F' k n) as Loop *)
      (*     by (intros; specialize (Sems k); eapply msem_node_loop; eauto). *)
      assert (forall n, r n = true -> F (count r n) n ≋ F (count r n) 0) as RstSpec
          by (intros; eapply msem_nodes_reset_spec; eauto).
      eapply SNode with (H := fun n => FH (count r n) n);
        try eapply clock_of_equiv;
        eauto;
        try (now intro n; specialize (Node (count r n));
             destruct Node as (Ins & Outs & Same & Same' & Abs & VarsCk & ? & Closed & Closed');
             specialize (Ins n); specialize (Outs n);
             specialize (Same n); specialize (Same' n);
             specialize (Abs n); specialize (VarsCk n);
             rewrite mask_transparent in Ins, Outs, Same, Same';
             rewrite 2 mask_transparent in Abs;
             unfold clock_of' in VarsCk; rewrite mask_transparent in VarsCk;
             auto).
      + assert (forall k, let bk := clock_of' (mask (all_absent (xs 0)) k r xs) in
                     Forall (msem_equation (node :: G) bk (mask false k r r') (FH k) (F k) (F' k)) (n_eqs node))
          as Heqs by (intro k; destruct (Node k); intuition).
        pose proof (find_node_not_Is_node_in _ _ _ Ord Find) as Hnini.
        clear - Heqs (* Loop *) RstSpec IHG Ord Hnini Length.
        induction (n_eqs node) as [|eq]; constructor; auto.
        *{ assert (forall k, let bk := clock_of' (mask (all_absent (xs 0)) k r xs) in
                        msem_equation (node :: G) bk (mask false k r r') (FH k) (F k) (F' k) eq) as Heq
               by (intro k; specialize (Heqs k); inv Heqs; auto).
           clear Heqs.
           set (H := fun n : nat => FH (count r n) n).
           set (bk := fun n => clock_of' (mask (all_absent (xs 0)) (count r n) r xs) n).
           assert (forall n, clock_of' xs n = bk n) as Clock
               by (intro; subst bk; simpl; unfold clock_of'; rewrite mask_transparent; auto).
           destruct eq.

           - apply SEqDef with (xs := fun n => interp_caexp_instant (bk n) (H n) c c0);
               intro n; specialize (Heq (count r n)); inv Heq;
                 erewrite <-interp_caexp_instant_sound; try rewrite Clock; eauto.

           - assert (exists x, hd_error i = Some x) as (x & Hx)
                 by (specialize (Heq 0); inv Heq; eauto).
             assert (exists Fx, forall k, sub_inst_n x (F k) (Fx k)) as (Fx & HMx).
             { assert (forall k, exists Mxk, sub_inst_n x (F k) Mxk) as HMx
                   by (intro k; specialize (Heq k);
                       inversion_clear Heq as [|?????????????? Hd|????????????????? Hd|];
                       rewrite Hd in Hx; inv Hx; eauto).
               apply functional_choice in HMx; auto.
             }
             assert (exists Fx', forall k, sub_inst_n x (F' k) (Fx' k)) as (Fx' & HMx').
             { assert (forall k, exists Mxk, sub_inst_n x (F' k) Mxk) as HMx'
                   by (intro k; specialize (Heq k);
                       inversion_clear Heq as [|?????????????? Hd|????????????????? Hd|];
                   rewrite Hd in Hx; inv Hx; eauto).
               apply functional_choice in HMx'; auto.
             }
             destruct o.
             + eapply SEqReset with
                   (Mx := fun n => match n with
                                | 0 => Fx (count r 0) 0
                                | S n => Fx' (count r n) n
                                end)
                   (Mx' := fun n => Fx' (count r n) n)
                   (xss := fun n => interp_vars_instant (H n) i)
                   (ls := fun n => interp_laexps_instant (bk n) (H n) c l0)
                   (ys := fun n => interp_var_instant (H n) i1)
                   (rs := fun n => match interp_var_instant (H n) i1 with
                                | absent => false
                                | present v => match val_to_bool v with
                                              | Some b => b
                                              | None => false
                                              end
                                end); eauto;
             try (intro n; specialize (Heq (count r n));
                  inversion_clear Heq as [| |??????????????????????? Rst|];
                  try erewrite <-interp_var_instant_sound;
                  try erewrite <-interp_vars_instant_sound;
                  try erewrite <-interp_laexps_instant_sound;
                  try rewrite Clock; eauto).
               *{ destruct n.
                  - specialize (HMx (count r 0)); auto.
                  - specialize (HMx' (count r n)); auto.
                }
               * specialize (HMx' (count r n)); auto.
               * specialize (Rst n).
                 destruct (ys n); simpl; auto.
                 simpl in *.
                 cases; auto; discriminate.
               *{ inv Ord.
                  apply msem_node_cons2; auto.
                  rewrite or_str_comm, <-or_str_assoc.
                  apply IHG; auto.
                  intro k; specialize (Heq k);
                    inversion_clear Heq as [| |????????????????? Hd' HFx HFx' Exps Vars Var Rst Node|].
                  rewrite Hd' in Hx; inv Hx.
                  eapply msem_node_cons in Node; auto using Ordered_nodes.
                  - rewrite or_str_comm.
                    apply sem_interp_laexps_instant_mask in Exps; eauto.
                    apply sem_interp_vars_instant_mask with (r := r) in Vars.
                    + eapply msem_node_eq_str; eauto.
                      * intro; specialize (HMx k n); specialize (HFx n).
                        unfold sub_inst in *; rewrite HFx in HMx; inv HMx; eauto.
                      * intro; specialize (HMx' k n); specialize (HFx' n).
                        unfold sub_inst in *; rewrite HFx' in HMx'; inv HMx'; eauto.
                      *{ rewrite mask_or_str.
                         assert (rs ≈ mask false k r
                                    (fun n =>
                                       match interp_var_instant (H n) i1 with
                                       | absent => false
                                       | present v => match val_to_bool v with
                                                     | Some b => b
                                                     | None => false
                                                     end
                                       end)) as <-; auto.
                         intro; specialize (Var n); apply interp_var_instant_sound in Var.
                         specialize (Rst n); rewrite Var in Rst.
                         subst H; simpl.
                         destruct (NPeano.Nat.eq_dec (count r n) k) as [E|].
                         - rewrite mask_transparent, E; auto.
                           destruct (interp_var_instant (FH k n) i1); simpl in Rst.
                           + inv Rst; auto.
                           + now rewrite Rst.
                         - rewrite mask_opaque; auto.
                           assert (interp_var_instant (FH k n) i1 = absent) as Abs by admit.
                           rewrite Abs in Rst; inv Rst; auto.
                       }
                    + inversion_clear Node as [??????????????? Abs].
                      intros; apply Abs.
                      rewrite Exps, mask_opaque; auto.
                      apply all_absent_spec.
                  - intro; subst; apply Hnini; left; constructor.
                }

             + eapply SEqApp with
                   (Mx := fun n => match n with
                                | 0 => Fx (count r 0) 0
                                | S n => Fx' (count r n) n
                                end)
                   (Mx' := fun n => Fx' (count r n) n)
                   (xss := fun n => interp_vars_instant (H n) i)
                   (ls := fun n => interp_laexps_instant (bk n) (H n) c l0);
                 eauto;
                 try (intro n; specialize (Heq (count r n));
                      inversion_clear Heq as [| |??????????????????????? Rst|];
                      try erewrite <-interp_vars_instant_sound;
                      try erewrite <-interp_laexps_instant_sound;
                      try rewrite Clock; eauto).
               *{ destruct n.
                  - specialize (HMx (count r 0)); auto.
                  - specialize (HMx' (count r n)); auto.
                }
               * specialize (HMx' (count r n)); auto.
               *{ inv Ord.
                  apply msem_node_cons2; auto.
                  apply IHG; auto.
                  intro k; specialize (Heq k);
                    inversion_clear Heq as [|?????????????? Hd' HFx HFx' Exps Vars Node| |].
                  rewrite Hd' in Hx; inv Hx.
                  eapply msem_node_cons in Node; auto using Ordered_nodes.
                  - apply sem_interp_laexps_instant_mask in Exps; eauto.
                    apply sem_interp_vars_instant_mask with (r := r) in Vars.
                    + eapply msem_node_eq_str; eauto.
                      * intro; specialize (HMx k n); specialize (HFx n).
                        unfold sub_inst in *; rewrite HFx in HMx; inv HMx; eauto.
                      * intro; specialize (HMx' k n); specialize (HFx' n).
                        unfold sub_inst in *; rewrite HFx' in HMx'; inv HMx'; eauto.
                    + inversion_clear Node as [??????????????? Abs].
                      intros; apply Abs.
                      rewrite Exps, mask_opaque; auto.
                      apply all_absent_spec.
                  - intro; subst; apply Hnini; left; constructor.
                }

           - apply SEqFby with (xs := fun n => interp_var_instant (H n) i)
                               (ls := fun n => interp_laexp_instant (bk n) (H n) c l0);
               try (intro n; specialize (Heq (count r n)); inv Heq;
                    try erewrite <-interp_laexp_instant_sound;
                    try erewrite <-interp_var_instant_sound; try rewrite Clock; eauto).
             split; [|split].
             + specialize (Heq (count r 0)); inversion_clear Heq as [| | |????????????? (?&?&?)]; auto.
             + intro n; specialize (Heq (count r n));
                 inversion_clear Heq as [| | |????????????? (Init & Loop' & Spec)]; auto.
             + pose proof Heq as Heq'.
               induction n.
               * specialize (Heq (count r 0));
                   inversion_clear Heq as [| | |????????????? (Init & ? & Spec)]; auto.
                 erewrite <-interp_laexp_instant_sound, <-interp_var_instant_sound; eauto.
                 specialize (Spec 0).
                 rewrite Init in *.
                 cases.
               *{ subst H bk; simpl in *.
                  specialize (Heq (count r n));
                    inversion_clear Heq as [| | |????????????? (Init_n & Loop_n & Spec_n)]; auto.
                  erewrite <-interp_laexp_instant_sound, <-interp_var_instant_sound in IHn; eauto.
                  destruct (r (S n)) eqn: R; unfold or_str; rewrite R; simpl.
                  - specialize (Heq' (S (count r n)));
                      inversion_clear Heq' as [| | |??????????? Exp ? (Init_Sn & Loop_Sn & Spec_Sn)]; auto.
                    erewrite <-interp_laexp_instant_sound, <-interp_var_instant_sound; eauto.
                    specialize (Spec_Sn (S n)).
                    assert (find_val i (F (S (count r n)) (S n)) = Some (sem_const c0)) as Find.
                    { rewrite <-Init_Sn.
                      replace (S (count r n)) with (count r (S n)).
                      - rewrite RstSpec; auto.
                      - simpl; rewrite R; auto.
                    }
                    rewrite Find in Spec_Sn.
                    destruct (ls0 (S n)).
                    + admit.
                    + destruct (find_val i match n with
                                           | 0 => F (if r 0 then 1 else 0) 0
                                           | S n0 => F' (count r n0) n0
                                           end) eqn: Find_n; try contradiction.
                      destruct (ls n); destruct IHn as (->); intuition; cases.
                  - erewrite <-interp_laexp_instant_sound, <-interp_var_instant_sound; eauto.
                    specialize (Spec_n (S n)).
                    destruct (find_val i (F (count r n) (S n))) eqn: Find; try contradiction.
                    rewrite Loop_n in Find; rewrite Find.
                    destruct (ls (S n)); auto.
                    rewrite mask_transparent in Spec_n; auto.
                    simpl; rewrite R; omega.
                }
         }
        *{ apply IHl.
           - intro k; specialize (Heqs k); inv Heqs; auto.
           - apply not_Is_node_in_cons in Hnini as (?&?); auto.
         }
      + destruct n.
        * destruct (Node (count r 0)) as (?&?&?&?&?&?&?&?&?); auto.
        * destruct (Node (count r n)) as (?&?&?&?&?&?&?&?&?); auto.
    - inv Ord.
      apply msem_node_cons2; auto.
      apply IHG; auto.
      intro k; specialize (Sems k); apply msem_node_cons in Sems;
        auto using Ordered_nodes.
      apply ident_eqb_neq; auto.
  Qed.

  Theorem sem_msem_reset:
    forall G f r xs ys,
      Ordered_nodes G ->
      (forall f xs ys,
          sem_node G f xs ys ->
          exists M M', msem_node G f (fun n => false) xs M M' ys) ->
      sem_reset G f r xs ys ->
      exists M M', msem_node G f r xs M M' ys.
  Proof.
    intros ** IH Sem.
    inversion_clear Sem as [???? Sem'].
    assert (exists F F', forall k, msem_node G f (mask false k r (fun n => false))
                                   (mask (all_absent (xs 0)) k r xs)
                                   (F k) (F' k)
                                   (mask (all_absent (ys 0)) k r ys))
      as (F & F' & Msem).
    { assert (forall k, exists Mk Mk', msem_node G f (mask false k r (fun n => false))
                                       (mask (all_absent (xs 0)) k r xs)
                                       Mk Mk'
                                       (mask (all_absent (ys 0)) k r ys)) as Msem'.
      { intro; specialize (Sem' k); apply IH in Sem' as (?&?&?); auto.
        do 2 eexists; eapply msem_node_eq_str_rst; eauto.
        intro; destruct (NPeano.Nat.eq_dec k (count r n)) eqn: E.
        - rewrite mask_transparent; auto.
        - rewrite mask_opaque; auto.
      }

      (** Infinite Description  *)
      do 2 apply functional_choice in Msem' as (?&Msem'); eauto.

      (** Epsilon  *)
      (* assert (inhabited memories) as I *)
      (*     by (constructor; exact (fun n => @empty_memory val)). *)
      (* exists (fun n => epsilon *)
      (*            I (fun M => msem_node G f (mask (all_absent (xs 0)) n r xs) M *)
      (*                               (mask (all_absent (ys 0)) n r ys))). *)
      (* intro; now apply epsilon_spec.  *)

      (** Constructive Epsilon  *)
      (* pose proof (constructive_ground_epsilon memories) as F. *)

      (** Classical Choice  *)
      (* now apply choice in Msem'.   *)
    }
    apply msem_node_slices in Msem; auto.
    do 2 eexists.
    eapply msem_node_eq_str_rst; eauto; try reflexivity.
    unfold or_str; intro; apply Bool.orb_false_r.
  Qed.

  Theorem sem_msem_node:
    forall G f xs ys,
      Ordered_nodes G ->
      sem_node G f xs ys ->
      exists M M', msem_node G f (fun n => false) xs M M' ys.
  Proof.
    induction G as [|node].
    inversion 2;
      match goal with Hf: find_node _ [] = _ |- _ => inversion Hf end.
    intros ** Hord Hsem.
    assert (Hsem' := Hsem).
    inversion_clear Hsem' as [??????? Hfind ?????? Heqs].
    pose proof (find_node_not_Is_node_in _ _ _ Hord Hfind) as Hnini.
    pose proof Hfind.
    simpl in Hfind.
    destruct (ident_eqb node.(n_name) f) eqn:Hnf.
    - assert (Hord':=Hord).
      inversion_clear Hord as [|? ? Hord'' Hnneqs Hnn].
      inv Hfind.
      eapply Forall_sem_equation_global_tl in Heqs; eauto.
      assert (forall f xs ys,
                 sem_node G f xs ys ->
                 exists M M', msem_node G f (fun n => false) xs M M' ys) as IHG'
          by auto.
      assert (forall f r xs ys,
                 sem_reset G f r xs ys ->
                 exists M M', msem_node G f r xs M M' ys) as IHG''
          by (intros; now apply sem_msem_reset).
      assert (exists M1 M1', Forall (msem_equation G bk (fun n => false) (restr_hist H) M1 M1') n.(n_eqs)
                        /\ memory_closed_n M1 n.(n_eqs)
                        /\ memory_closed_n M1' n.(n_eqs))
        as (M1 & M1' & Hmsem & ?&?)
          by (eapply sem_msem_eqs; eauto; apply NoDup_defs_node).
      exists M1, M1'.
      econstructor; eauto.
      rewrite <-msem_equations_cons; eauto.
    - apply ident_eqb_neq in Hnf.
      apply sem_node_cons with (1:=Hord) (3:=Hnf) in Hsem.
      inv Hord.
      eapply IHG in Hsem as (M & M' &?); eauto.
      exists M, M'.
      now eapply msem_node_cons2; eauto.
  Qed.


  (** Initial memory *)


  Lemma msem_eqs_same_initial_memory:
    forall M1 M1' G eqs bk1 r1 H1 M2 M2' bk2 r2 H2,
    (forall f r1 xss1 M1 M1' yss1 r2 xss2 M2 M2' yss2,
        msem_node G f r1 xss1 M1 M1' yss1 ->
        msem_node G f r2 xss2 M2 M2' yss2 ->
        M1 0 ≋ M2 0) ->
    NoDup_defs eqs ->
    memory_closed_n M1 eqs ->
    memory_closed_n M2 eqs ->
    Forall (msem_equation G bk1 r1 H1 M1 M1') eqs ->
    Forall (msem_equation G bk2 r2 H2 M2 M2') eqs ->
    M1 0 ≋ M2 0.
  Proof.
    intros ** IH Nodup Closed1 Closed2 Heqs1 Heqs2.
    revert dependent M1; revert dependent M2; revert M1' M2'.
    induction eqs as [|[] ? IHeqs]; intros;
      inversion_clear Heqs1 as [|?? Sem1 Sems1];
      inversion_clear Heqs2 as [|?? Sem2 Sems2];
      try inversion Sem1 as [|?????????????? Hd1 ???? Node|
                             ????????????????? Hd1 ?????? Node|
                             ????????????? Mfby1];
      try inversion Sem2 as [|?????????????? Hd2|
                             ????????????????? Hd2|
                             ????????????? Mfby2];
      inv Nodup; subst; try discriminate; eauto.
    - assert (forall n, M1 n ≋ empty_memory _) as ->
          by (intro; apply memory_closed_empty; auto).
      assert (forall n, M2 n ≋ empty_memory _) as ->
          by (intro; apply memory_closed_empty; auto).
      reflexivity.

    - rewrite Hd2 in Hd1; inv Hd1.
      assert (~ Is_defined_in_eqs x eqs)
        by (apply hd_error_Some_In in Hd2; auto).
      apply msem_equation_remove_inst with (x := x) in Sems1;
        apply msem_equation_remove_inst with (x := x) in Sems2; auto.
      eapply IHeqs in Sems1; eauto; try eapply memory_closed_n_App'; eauto.
      erewrite add_remove_inst_same; eauto;
        symmetry; erewrite add_remove_inst_same; eauto.
      rewrite Sems1.
      eapply IH in Node; eauto.
      now rewrite Node.

    - rewrite Hd2 in Hd1; inv Hd1.
      assert (~ Is_defined_in_eqs x eqs)
        by (apply hd_error_Some_In in Hd2; auto).
      apply msem_equation_remove_inst with (x := x) in Sems1;
        apply msem_equation_remove_inst with (x := x) in Sems2; auto.
      eapply IHeqs in Sems1; eauto; try eapply memory_closed_n_App'; eauto.
      erewrite add_remove_inst_same; eauto;
        symmetry; erewrite add_remove_inst_same; eauto.
      rewrite Sems1.
      eapply IH in Node; eauto.
      now rewrite Node.

    - apply msem_equation_remove_val with (x := i) in Sems1;
        apply msem_equation_remove_val with (x := i) in Sems2; auto.
      eapply IHeqs in Sems1; eauto; try eapply memory_closed_n_Fby'; eauto.
      destruct Mfby1, Mfby2.
      erewrite add_remove_val_same; eauto;
        symmetry; erewrite add_remove_val_same; eauto.
      now rewrite Sems1.
  Qed.

  Theorem same_initial_memory:
    forall G f r1 r2 xss1 xss2 M1 M2 M1' M2' yss1 yss2,
      Ordered_nodes G ->
      msem_node G f r1 xss1 M1 M1' yss1 ->
      msem_node G f r2 xss2 M2 M2' yss2 ->
      M1 0 ≋ M2 0.
  Proof.
    induction G as [|node].
    inversion 2;
      match goal with Hf: find_node _ [] = _ |- _ => inversion Hf end.
    intros ** Hord Hsem1 Hsem2.
    assert (Hsem1' := Hsem1);  assert (Hsem2' := Hsem2).
    inversion_clear Hsem1' as [????????? Clock1 Hfind1 Ins1 ????? Heqs1];
      inversion_clear Hsem2' as [????????? Clock2 Hfind2 Ins2 ????? Heqs2].
    rewrite Hfind2 in Hfind1; inv Hfind1.
    pose proof Hord; inv Hord.
    pose proof Hfind2.
    simpl in Hfind2.
    destruct (ident_eqb node.(n_name) f) eqn:Hnf.
    - inv Hfind2.
      assert (~ Is_node_in (n_name node0) (n_eqs node0))
        by (eapply find_node_not_Is_node_in; eauto).
      eapply msem_equations_cons in Heqs1; eauto.
      eapply msem_equations_cons in Heqs2; eauto.
      eapply msem_eqs_same_initial_memory; eauto.
      apply NoDup_defs_node.
    - assert (n_name node <> f) by now apply ident_eqb_neq.
      eapply msem_node_cons in Hsem1; eapply msem_node_cons in Hsem2; eauto.
  Qed.




  (** Absent  *)

  Lemma mfby_absent:
    forall n x v0 ls rs M M' xs,
      mfby x v0 ls rs M M' xs ->
      ls n = absent ->
      find_val x (M' n) = find_val x (M n).
  Proof.
    induction n; intros ** Mfby Abs;
      destruct Mfby as (Init & Spec & Spec').
    - specialize (Spec' 0); rewrite Init, Abs in Spec'.
      intuition; congruence.
    - (* rewrite Spec. *)
      specialize (Spec' (S n)).
      destruct (find_val x (M (S n))); try contradiction.
      rewrite Abs in Spec'.
      intuition.
  Qed.

  Lemma msem_eqs_absent:
    forall M M' G eqs bk rs H n,
    (forall f r xss M M' yss n,
        msem_node G f r xss M M' yss ->
        absent_list (xss n) ->
        M' n ≋ M n) ->
    Ordered_nodes G ->
    bk n = false ->
    NoDup_defs eqs ->
    memory_closed_n M eqs ->
    memory_closed_n M' eqs ->
    Forall (msem_equation G bk rs H M M') eqs ->
    M' n ≋ M n.
  Proof.
    intros ** IH Hord Absbk Nodup Closed Closed' Heqs.
    revert dependent M; revert dependent M'.
    induction eqs as [|[] ? IHeqs]; intros;
      inversion_clear Heqs as [|?? Sem Sems];
      try inversion_clear Sem as [|
                                  ?????????????? Hd ?? Args ? Node|
                                  ????????????????? Hd ?? Args ??? Node|
                                  ??????????? Arg ? Mfby];
      inv Nodup; eauto.
    - assert (forall n, M n ≋ empty_memory _) as E
          by (intro; apply memory_closed_empty; auto).
     assert (forall n, M' n ≋ empty_memory _) as E'
          by (intro; apply memory_closed_empty; auto).
     rewrite E, E'; reflexivity.

    - apply msem_equation_remove_inst with (x := x) in Sems.
      + apply IHeqs in Sems; try eapply memory_closed_n_App'; eauto.
        apply IH with (n := n) in Node; auto.
        * erewrite add_remove_inst_same; eauto;
            symmetry; erewrite add_remove_inst_same; eauto.
          now rewrite Sems, Node.
        * specialize (Args n); simpl in Args.
          rewrite Absbk in Args.
          inversion_clear Args as [?????? SClock|??? ->]; try apply all_absent_spec.
          contradict SClock; apply not_subrate_clock.
      + apply hd_error_Some_In in Hd; auto.

    - apply msem_equation_remove_inst with (x := x) in Sems.
      + apply IHeqs in Sems; try eapply memory_closed_n_App'; eauto.
        apply IH with (n := n) in Node; auto.
        * erewrite add_remove_inst_same; eauto;
            symmetry; erewrite add_remove_inst_same; eauto.
          now rewrite Sems, Node.
        * specialize (Args n); simpl in Args.
          rewrite Absbk in Args.
          inversion_clear Args as [?????? SClock|??? ->]; try apply all_absent_spec.
          contradict SClock; apply not_subrate_clock.
      + apply hd_error_Some_In in Hd; auto.

    - apply msem_equation_remove_val with (x := i) in Sems; auto.
      apply IHeqs in Sems; try eapply memory_closed_n_Fby'; eauto.
      assert (find_val i (M' n) = find_val i (M n)) as E.
      { eapply mfby_absent; eauto.
        specialize (Arg n); simpl in Arg.
        rewrite Absbk in Arg.
        inversion_clear Arg as [???? SClock|]; auto.
        contradict SClock; apply not_subrate_clock.
      }
      destruct Mfby as (Init & Loop & Spec').
      specialize (Spec' n).
      destruct (find_val i (M' n)) eqn: Eq', (find_val i (M n)) eqn: Eq;
        try contradiction; inv E.
      erewrite add_remove_val_same; eauto;
        symmetry; erewrite add_remove_val_same; eauto.
      now rewrite Sems.
  Qed.

  Theorem msem_node_absent:
    forall G f r xss M M' yss n,
      Ordered_nodes G ->
      msem_node G f r xss M M' yss ->
      absent_list (xss n) ->
      M' n ≋ M n.
  Proof.
    induction G as [|node].
    inversion 2;
      match goal with Hf: find_node _ [] = _ |- _ => inversion Hf end.
    intros ** Hord Hsem Abs.
    assert (Hsem' := Hsem).
    inversion_clear Hsem' as [????????? Clock Hfind Ins ????? Heqs].
    assert (bk n = false) as Absbk.
    { rewrite <-Bool.not_true_iff_false.
      intro E; apply Clock in E.
      specialize (Ins n).
      apply Forall2_length in Ins.
      destruct (xss n).
      - rewrite map_length in Ins; simpl in Ins.
        pose proof (n_ingt0 node0); omega.
      - inv E; inv Abs; congruence.
    }
    pose proof (find_node_not_Is_node_in _ _ _ Hord Hfind) as Hnini.
    pose proof Hord; inv Hord.
    pose proof Hfind.
    simpl in Hfind.
    destruct (ident_eqb node.(n_name) f) eqn:Hnf.
    - inv Hfind.
      eapply msem_equations_cons in Heqs; eauto.
      eapply msem_eqs_absent; eauto.
      apply NoDup_defs_node.
    - eapply msem_node_cons in Hsem; eauto.
      now apply ident_eqb_neq.
  Qed.

  (** The other way around  *)

  Lemma mfby_fby:
    forall x v0 es M M' xs,
      mfby x v0 es (fun n => false) M M' xs ->
      xs ≈ fby v0 es.
  Proof.
    intros ** (Init & Loop & Spec) n.
    unfold fby.
    pose proof (Spec n) as Spec'.
    destruct (find_val x (M n)) eqn: Find_n; try contradiction.
    destruct (es n); destruct Spec' as (?& Hx); auto.
    rewrite Hx.
    clear - Init Loop Spec Find_n.
    revert dependent v.
    induction n; intros; simpl; try congruence.
    specialize (Spec n).
    destruct (find_val x (M n)); try contradiction.
    rewrite Loop in Find_n.
    destruct (es n); destruct Spec; try congruence.
    apply IHn; congruence.
  Qed.

  (* Theorem msem_sem_node_equation_reset: *)
  (*   forall G, *)
  (*     (forall f xss M M' yss, *)
  (*         msem_node G f (fun n => false) xss M M' yss -> *)
  (*         sem_node G f xss yss) *)
  (*     /\ *)
  (*     (forall bk H M M' eq, *)
  (*         msem_equation G bk (fun n => false) H M M' eq -> *)
  (*         sem_equation G bk H eq). *)
  (* Proof. *)
  (*   intros; apply msem_node_equation_reset_ind; *)
  (*     [intros|intros|intros|intros|intros ?????? IH|intros]; *)
  (*     eauto using sem_equation, mfby_fby, sem_node. *)
  (*   constructor; intro; destruct (IH k) as (?&?&?); intuition. *)
  (* Qed. *)

  (* Corollary msem_sem_node: *)
  (*   forall G f xss M M' yss, *)
  (*     msem_node G f xss M M' yss -> *)
  (*     sem_node G f xss yss. *)
  (* Proof. *)
  (*   intros; eapply (proj1 (msem_sem_node_equation_reset G)); eauto. *)
  (* Qed. *)

  (* Corollary msem_sem_equation: *)
  (*   forall G bk H M M' eq, *)
  (*     msem_equation G bk H M M' eq -> *)
  (*     sem_equation G bk H eq. *)
  (* Proof. *)
  (*   intros; eapply (proj1 (proj2 (msem_sem_node_equation_reset G))); eauto. *)
  (* Qed. *)

  (* Corollary msem_sem_equations: *)
  (*   forall G bk H M M' eqs, *)
  (*     Forall (msem_equation G bk H M M') eqs -> *)
  (*     Forall (sem_equation G bk H) eqs. *)
  (* Proof. *)
  (*   induction 1; constructor; eauto using msem_sem_equation. *)
  (* Qed. *)

End MEMSEMANTICS.

Module MemSemanticsFun
       (Ids     : IDS)
       (Op      : OPERATORS)
       (OpAux   : OPERATORS_AUX   Op)
       (Clks    : CLOCKS          Ids)
       (ExprSyn : NLEXPRSYNTAX        Op)
       (Syn     : NLSYNTAX        Ids Op       Clks ExprSyn)
       (Str     : STREAM              Op OpAux)
       (Ord     : ORDERED         Ids Op       Clks ExprSyn Syn)
       (ExprSem : NLEXPRSEMANTICS Ids Op OpAux Clks ExprSyn     Str)
       (Sem     : NLSEMANTICS     Ids Op OpAux Clks ExprSyn Syn Str Ord ExprSem)
       (Mem     : MEMORIES        Ids Op       Clks ExprSyn Syn)
       (IsD     : ISDEFINED       Ids Op       Clks ExprSyn Syn                 Mem)
       (IsV     : ISVARIABLE      Ids Op       Clks ExprSyn Syn                 Mem IsD)
       (IsF     : ISFREE          Ids Op       Clks ExprSyn Syn)
       (NoD     : NODUP           Ids Op       Clks ExprSyn Syn                 Mem IsD IsV)
       <: MEMSEMANTICS Ids Op OpAux Clks ExprSyn Syn Str Ord ExprSem Sem Mem IsD IsV IsF NoD.
  Include MEMSEMANTICS Ids Op OpAux Clks ExprSyn Syn Str Ord ExprSem Sem Mem IsD IsV IsF NoD.
End MemSemanticsFun.
