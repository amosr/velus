Require Import List.

Require Import Velus.Common.
Require Import Velus.Operators.
Require Import Velus.Clocks.
Require Import Velus.RMemory.
Require Import Velus.NLustre.
Require Import Velus.Obc.

(** * Correspondence between dataflow and imperative memories *)

Module Type MEMORYCORRES
       (Ids         : IDS)
       (Op          : OPERATORS)
       (OpAux       : OPERATORS_AUX Op)
       (Import Clks : CLOCKS Ids)
       (Import DF   : NLUSTRE Ids Op OpAux Clks)
       (Import MP   : OBC Ids Op OpAux).
(**

  [Memory_Corres] relates a dataflow [D.memory] with an object [heap]
  at an instant [n]. Morally, we are saying that taking a snapshot of
  the memory at time [n] gives [heap].

 *)

  Inductive Memory_Corres (G: global) (n: nat) :
    ident -> memory -> heap -> Prop :=
  | MemC:
      forall f M menv i o v eqs ingt0 outgt0 defd vout nodup good,
        find_node f G = Some(mk_node f i o v eqs ingt0 outgt0 defd vout nodup good)
        -> List.Forall (Memory_Corres_eq G n M menv) eqs
        -> Memory_Corres G n f M menv

  with Memory_Corres_eq (G: global) (n: nat) :
         memory -> heap -> equation -> Prop :=
       | MemC_EqDef:
           forall M menv x ck ce,
             Memory_Corres_eq G n M menv (EqDef x ck ce)
       | MemC_EqApp: forall M menv x xs ck f le,
           (* =Memory_Corres_eq:eqapp= *)
           hd_error xs = Some x ->
           (forall Mo, mfind_inst x M = Some Mo ->
                  (exists omenv, mfind_inst x menv = Some omenv
                                 /\ Memory_Corres G n f Mo omenv))
           -> Memory_Corres_eq G n M menv (EqApp xs ck f le)(*,*)
       (* =end= *)
       | MemC_EqFby: forall M menv x ck v0 le,
           (* =Memory_Corres_eq:eqfby= *)
           (forall ms, mfind_mem x M = Some ms ->
                       mfind_mem x menv = Some (ms n))
           -> Memory_Corres_eq G n M menv (EqFby x ck v0 le)(*.*)
  (* =end= *)
  .

  (** ** Induction principle for [Memory_Corres] and [Memory_Corres_eq] *)

  Section Memory_Corres_mult.
    Variables (G: global) (n: nat).

    Variable P : ident -> memory -> heap -> Prop.
    Variable Peq : memory -> heap -> equation -> Prop.

    Hypothesis EqDef_case: forall M menv x ck ce,
        Peq M menv (EqDef x ck ce).

    Hypothesis EqApp_case: forall M menv x xs ck f le,
        hd_error xs = Some x ->
        (forall Mo
           (Hmfind: mfind_inst x M = Some Mo),
            (exists omenv, mfind_inst x menv = Some omenv /\ P f Mo omenv))
        -> Peq M menv (EqApp xs ck f le).

    Hypothesis EqFby_case: forall M menv x ck v0 le,
        (forall ms, mfind_mem x M = Some ms
               -> mfind_mem x menv = Some (ms n))
        -> Peq M menv (EqFby x ck v0 le).

    Hypothesis MemC_case:
      forall f M menv i o v eqs ingt0 outgt0 defd vout nodup good
        (Hfind : find_node f G =
                   Some (mk_node f i o v eqs ingt0 outgt0 defd vout nodup good)),
        Forall (Peq M menv) eqs
        -> P f M menv.

    Fixpoint Memory_Corres_mult (f    : ident)
             (M    : memory)
             (menv : heap)
             (Hmc  : Memory_Corres G n f M menv)
             {struct Hmc} : P f M menv :=
      match Hmc in (Memory_Corres _ _ f M menv) return (P f M menv) with
      | MemC f M menv i o v eqs ingt0 outgt0 defd vout nodup good Hfind Heqs =>
        MemC_case f M menv i o v eqs ingt0 outgt0 defd vout nodup good Hfind
                  (* Turn: Forall (Memory_Corres_eq G n M menv) eqs
             into: Forall (Peq M menv) eqs *)
                  ((fix map (eqs : list equation)
                        (Heqs: Forall (Memory_Corres_eq G n M menv) eqs) :=
                      match Heqs in Forall _ fs return (Forall (Peq M menv) fs)
                      with
                      | Forall_nil => Forall_nil _
                      | Forall_cons eq eqs Heq Heqs' =>
                        Forall_cons eq (Memory_Corres_eq_mult M menv eq Heq)
                                    (map eqs Heqs')
                      end) eqs Heqs)
      end

    with Memory_Corres_eq_mult (M     : memory)
                               (menv  : heap)
                               (eq    : equation)
                               (Hmceq : Memory_Corres_eq G n M menv eq)
                               {struct Hmceq} : Peq M menv eq.
    refine(
        match Hmceq in (Memory_Corres_eq _ _ M menv eq) return (Peq M menv eq)
        with
        | MemC_EqDef M menv x ck ce => EqDef_case M menv x ck ce
        | MemC_EqApp M menv x xs ck f le Hsome Hmc =>
          EqApp_case M menv x xs ck f le Hsome
                     (fun (Mo     : memory)
                        (Hmfind : mfind_inst x M = Some Mo) => _)
        | MemC_EqFby M menv x ck v0 lae Hfind =>
              EqFby_case M menv x ck v0 lae Hfind
        end).
    specialize (Hmc Mo Hmfind).
    destruct Hmc as [omenv [Hfindo Hmc]].
    exists omenv.
    apply Memory_Corres_mult in Hmc.
    split; [exact Hfindo|exact Hmc].
    Defined.

  End Memory_Corres_mult.

  (** ** Global environment management *)

  Lemma Memory_Corres_eq_node_tl:
    forall node G eq n M menv,
      Ordered_nodes (node::G)
      -> ~Is_node_in_eq node.(n_name) eq
      -> (Memory_Corres_eq (node::G) n M menv eq
         <-> Memory_Corres_eq G n M menv eq).
  Proof.
    intros node G eqs n M menv Hord Hini.
    split; intro Hmc; revert M menv eqs Hmc Hini.
    - induction 1 as [
                     | ? ? ? ? ? ? ? Hsome Hfind
                     | ? ? ? ? ? ? Hfind
                     | ? ? ? ? ? ? ? ? ? ? ? ? ? Hfindn IH]
                       using Memory_Corres_eq_mult
                     with (P:=fun f M menv=>
                                node.(n_name) <> f ->
                                Memory_Corres G n f M menv);
        intro HH; try solve [ constructor(auto) | intuition].

      + (* Case: Memory_Corres_eq G n M menv (EqApp xs ck f le) *)
        assert (n_name node <> f)
          by (intro; subst; apply HH; auto using Is_node_in_eq).

        econstructor; eauto.
        intros; edestruct Hfind as (? & Hinst & Hcorres); eauto.

      + (* Case: Memory_Corres G n f M menv *)
        simpl in Hfindn.
        apply ident_eqb_neq in HH.
        rewrite HH in Hfindn.
        econstructor; [exact Hfindn|].
        apply find_node_later_not_Is_node_in with (2:=Hfindn) in Hord.
        simpl in Hord; clear Hfindn.
        apply Is_node_in_Forall in Hord.
        apply Forall_Forall with (1:=Hord) in IH.
        apply Forall_impl with (2:=IH).
        intuition.

    - induction 1 as [
                     | ? ? ? ? ? ? ? Hsome Hfind
                     | ? ? ? ? ? ? Hfind
                     |? ? ? ? ? ? ? ? ? ? ? ? ? Hfindn IH]
                       using Memory_Corres_eq_mult
                     with (P:=fun f M menv=>
                                node.(n_name) <> f ->
                                Memory_Corres (node :: G) n f M menv);
      intro HH; try solve [ constructor; auto | intuition].
      + assert (n_name node <> f)
          by (intro; subst; apply HH; auto using Is_node_in_eq).
        econstructor; eauto.
        intros Mo Hmfind.
        edestruct Hfind as (? & Hinst & Hcorres); eauto.

      + apply find_node_later_not_Is_node_in with (2:=Hfindn) in Hord.
        rewrite <-find_node_tl with (1:=HH) in Hfindn.
        econstructor; [exact Hfindn|].
        apply Is_node_in_Forall in Hord.
        apply Forall_Forall with (1:=Hord) in IH.
        apply Forall_impl with (2:=IH).
        intuition.
  Qed.

  Lemma Memory_Corres_eqs_node_tl:
    forall node G eqs n M menv,
      Ordered_nodes (node::G)
      -> ~Is_node_in node.(n_name) eqs
      -> (Forall (Memory_Corres_eq (node::G) n M menv) eqs
         <-> Forall (Memory_Corres_eq G n M menv) eqs).
  Proof.
    induction eqs as [|eq eqs IH]; [now intuition|].
    intros n M menv Hord Hnini.
    apply not_Is_node_in_cons in Hnini.
    destruct Hnini as [Hnini Hninis].
    split;
      intro HH; apply Forall_cons2 in HH; destruct HH as [HH HHs];
      apply Forall_cons;
      (apply Memory_Corres_eq_node_tl with (1:=Hord) (2:=Hnini) (3:=HH)
       || apply IH with (1:=Hord) (2:=Hninis) (3:=HHs)).
  Qed.

  Lemma Memory_Corres_node_tl:
    forall f node G n M menv,
      Ordered_nodes (node :: G)
      -> node.(n_name) <> f
      -> (Memory_Corres (node :: G) n f M menv <-> Memory_Corres G n f M menv).
  Proof.
    intros f node G n M menv Hord Hnf.
    split;
      inversion_clear 1;
      econstructor;
      repeat progress
             match goal with
             | Hf: find_node ?f (_ :: ?G) = Some _ |- _ =>
               rewrite find_node_tl with (1:=Hnf) in Hf
             | |- find_node ?f (_ :: ?G) = Some _ =>
               rewrite find_node_tl with (1:=Hnf)
             | Hf: find_node ?f ?G = Some _ |- find_node ?f ?G = Some _ =>
               exact Hf
             | H:Forall (Memory_Corres_eq _ _ _ _) _
               |- Forall (Memory_Corres_eq _ _ _ _) _ =>
               apply Memory_Corres_eqs_node_tl with (1:=Hord) (3:=H)
             | Hf: find_node ?f ?G = Some _ |- ~Is_node_in _ _ =>
               apply find_node_later_not_Is_node_in with (1:=Hord) (2:=Hf)
             end.
  Qed.

  (** ** Memory management *)

  Lemma Is_memory_in_Memory_Corres_eqs:
    forall G n M menv x eqs,
      Is_defined_in_eqs x eqs
      -> ~Is_variable_in_eqs x eqs
      -> Forall (Memory_Corres_eq G n M menv) eqs
      -> (forall ms, mfind_mem x M = Some ms
               -> mfind_mem x menv = Some (ms n)).
  Proof.
    induction eqs as [|eq eqs IH]; [now inversion 1|].
    intros Hidi Hnvi Hmc ms.
    apply Is_defined_in_cons in Hidi.
    apply not_Is_variable_in_cons in Hnvi.
    destruct Hnvi as [Hnvi Hnvis].
    inversion_clear Hmc as [|? ? Hmceq Hmceqs].
    destruct Hidi as [Himeqs|[Himeq Himeqs]];
      [|now apply IH with (1:=Himeqs) (2:=Hnvis) (3:=Hmceqs)].
    destruct eq;
      inversion Himeqs; subst;
      try (exfalso; apply Hnvi; now constructor).
    inversion_clear Hmceq; auto.
  Qed.

  Lemma Memory_Corres_eqs_add_mem:
    forall G M menv n y ms eqs,
      mfind_mem y M = Some ms
      -> Forall (Memory_Corres_eq G n M menv) eqs
      -> Forall (Memory_Corres_eq G n M (madd_mem y (ms n) menv)) eqs.
  Proof.
    induction eqs as [|eq eqs IH]; [now auto|].
    intros Hmfind Hmc.

    assert (  Memory_Corres_eq G n M menv eq
            /\ Forall (Memory_Corres_eq G n M menv) eqs)
      as (Hmc0 & ?)
      by now apply Forall_cons2. clear Hmc.

    apply Forall_cons; [|eapply IH; eauto].
    destruct eq.
    - (* Case: eq ~ EqDef *)
      now constructor.
    - (* Case: eq ~ EqApp *)
      inversion_clear Hmc0 as [|? ? x ? ? ? ? Hsome Hmc|].
      econstructor; eauto.
    - (* Case: eq ~ EqFby *)
      constructor.
      intros ms' Hmfind'.
      destruct (ident_eq_dec i y) as [He|Hne].
      + subst i.
        rewrite Hmfind in Hmfind'.
        injection Hmfind'; intro; subst ms.
        now rewrite mfind_mem_gss.
      + erewrite mfind_mem_gso; auto.
        inversion_clear Hmc0 as [| |? ? ? ? ? ? Hmc].
        now eapply Hmc.
  Qed.

  (* Unfortunately, a similar lemma to Memory_Corres_eqs_add_mem but for add_obj
   does not seem to hold without extra conditions:

     Lemma Memory_Corres_eqs_add_obj:
       forall G n M menv y Mo g omenv eqs,
         mfind_inst y M = Some Mo
         -> Memory_Corres G n g Mo omenv
         -> Memory_Corres_eqs G n M menv eqs
         -> Memory_Corres_eqs G n M (add_obj y omenv menv) eqs.

   Consider the equations:
      [ x = f y; x = g y; ... ]
   It is possible for this system to have an m-semantics if both f and g have
   the same input/output behaviour, but also possible for the memory structures
   of f and g to differ from one another. In this case, we end up having as
   hypothesis
        Memory_Corres G n g Mo omenv
   and the goal
        Memory_Corres G n f Mo omenv *)

  Lemma Memory_Corres_eqs_add_obj:
    forall G n M menv eqs y omenv,
      Forall (Memory_Corres_eq G n M menv) eqs
      -> ~Is_defined_in_eqs y eqs
      -> Forall (Memory_Corres_eq G n M (madd_obj y omenv menv)) eqs.
  Proof.
    induction eqs as [|eq eqs IH]; [now constructor|].
    intros y omenv Hmce Hniii.

    assert (  Memory_Corres_eq G n M menv eq
            /\ Forall (Memory_Corres_eq G n M menv) eqs)
      as (Hmc0 & ?)
      by now apply Forall_cons2. clear Hmce.

    assert (  ~ Is_defined_in_eq y eq
            /\ ~ Is_defined_in_eqs y eqs)
      as (Hniii0 & Hniii1)
        by now apply not_Is_defined_in_cons.

    apply Forall_cons; [|now eapply IH].

    destruct eq.
    - (* Case: EqDef *)
      now constructor.
    - (* Case: EqApp *)
      inversion_clear Hmc0 as [| ? ? ? ? ? ? ? Hsome Hfindo |].
      econstructor; eauto.

      intros Mo Hmfind.
      destruct (ident_eq_dec x y) as [Hxy|Hnxy].
      + subst x. exfalso; apply Hniii0; constructor.
        destruct i; simpl in *; try discriminate.
        left. now injection Hsome.
      + edestruct Hfindo as [omenv' [Hfindo' Hmc]]; eauto.
        exists omenv'.
        split; eauto.
        now rewrite mfind_inst_gso.
    - constructor.
      intros ms Hmfind.
      rewrite mfind_mem_add_inst.
      now (inv Hmc0; eauto).
  Qed.

  Lemma Memory_Corres_unchanged:
    forall G f n ls M ys menv,
      Welldef_global G
      -> msem_node G f ls M ys
      -> absent_list (ls n)
      -> Memory_Corres G n f M menv
      -> Memory_Corres G (S n) f M menv.
  Proof.
    intros G f n ls M ys menv Hwdef Hmsem Habs.
    revert menv.
    induction Hmsem
      as [| bk H M y ys ck f M' les ls yS Hsome Hmfind Hls Hys Hmsem IH
          | bk H M ms y ck ls yS v0 lae Hmfind Hms0 Hls HyS Hy
          | bk f xs M ys i o v eqs ingt0 outgt0 defd vout nodup good Hbk Hf Heqs IH]
           using msem_node_mult
         with (P := fun bk H M eq Hsem =>
                      forall menv,
                        rhs_absent_instant (bk n) (restr H n) eq
                        -> Memory_Corres_eq G n M menv eq
                        -> Memory_Corres_eq G (S n) M menv eq).
    - (* Case: EqDef *)
      inversion_clear 2; constructor; assumption.
    - intros Hrhsa Hmceq.
      econstructor; eauto.
      intros Mo Hmfind'.
      rewrite Hmfind in Hmfind'.
      injection Hmfind'; intro Heq; rewrite <-Heq; clear Heq Hmfind'.

      inversion_clear Hmceq as [|? ? ? ? ? ? ? ? Hmc'|].
      assert (Some x = Some y)
        as Hxy
        by now rewrite Hsome, <- H0.
      injection Hxy; intro; subst x.

      edestruct Hmc' as [omenv [Hfindo Hmc]]; eauto.
      exists omenv.
      split; [exact Hfindo|].
      apply IH with (2:=Hmc).
      inversion_clear Hrhsa as [|? ? ? ? ? Hlaea Hvs |].

      assert (ls n = vs)
        by (specialize (Hls n); simpl in Hls; sem_det).
      now unfold absent_list; subst vs.
    - rename Habs into menv.
      intros Hdefabs Hmceq.
      constructor.
      intros ms0 Hmfind0.
      rewrite Hmfind in Hmfind0.
      injection Hmfind0; intro Heq; rewrite <-Heq; clear Heq Hmfind0 ms0.
      inversion_clear Hmceq as [| |? ? ? ? ? ? Hmenv].
      apply Hmenv in Hmfind.
      rewrite Hmfind.
      inversion_clear Hdefabs as [| |? ? ? Hlaea].
      specialize (Hls n); simpl in Hls.
      specialize Hy with n.
      assert (Hls_abs: ls n = absent) by sem_det.
      rewrite Hls_abs in Hy.
      now f_equal.
    - intros menv Hmc.
      inversion_clear Hmc
        as [? ? ? i' o' v' eqs' ingt0' outgt0' defd' vout' nodup' good' Hf' Hmceqs].
      rewrite Hf in Hf'.
      injection Hf'.
      intros HR1 HR2 HR3 HR4;
        rewrite <-HR1 in *;
        clear ingt0' outgt0' defd' vout' nodup' good' i' o' v' eqs' Hf'
              HR1 HR2 HR3 HR4.
      clear Heqs.
      destruct IH as (H & Hxs & Hys & Hout & Hsamexs & Hsameys & HH).

      assert (Forall (msem_equation G bk H M) eqs).
      {
        rewrite Forall_forall in HH.
        rewrite Forall_forall; intros.
        specialize (HH x H0).
        destruct HH. eauto.
      }

      assert (0 < length (xs n)).
      {
        unfold sem_vars, lift in Hxs.
        specialize Hxs with n.
        apply Forall2_length in Hxs.
        rewrite map_length in Hxs.
        rewrite <-Hxs.
        exact ingt0.
      }

      assert (Habs': absent_list (xs n) ->
                     List.Forall (rhs_absent_instant (bk n) (restr H n)) eqs)
        by (eapply subrate_property_eqns; eauto).

      apply Habs' in Habs.
      apply Forall_Forall with (1:=Habs) in HH.
      apply Forall_Forall with (1:=Hmceqs) in HH.
      clear Habs Hmceqs.
      econstructor; [exact Hf|].
      apply Forall_impl with (2:=HH); clear HH.
      intros eq HH.
      destruct HH as [Hmceq [Habseq [Hmsem HH]]].
      eapply HH; eauto.
  Qed.

End MEMORYCORRES.

Module MemoryCorresFun
       (Ids   : IDS)
       (Op    : OPERATORS)
       (OpAux : OPERATORS_AUX Op)
       (Clks  : CLOCKS Ids)
       (DF    : NLUSTRE Ids Op OpAux Clks)
       (MP    : OBC Ids Op OpAux)
       <: MEMORYCORRES Ids Op OpAux Clks DF MP.
  Include MEMORYCORRES Ids Op OpAux Clks DF MP.
End MemoryCorresFun.     