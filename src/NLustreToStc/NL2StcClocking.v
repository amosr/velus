(* *********************************************************************)
(*                                                                     *)
(*                 The Vélus verified Lustre compiler                  *)
(*                                                                     *)
(*             (c) 2019 Inria Paris (see the AUTHORS file)             *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique. All rights reserved. This file is distributed under   *)
(*  the terms of the INRIA Non-Commercial License Agreement (see the   *)
(*  LICENSE file).                                                     *)
(*                                                                     *)
(* *********************************************************************)

From Velus Require Import NLustre.
From Velus Require Import Stc.

From Velus Require Import NLustreToStc.Translation.

From Velus Require Import VelusMemory.
From Velus Require Import Common.

From Coq Require Import List.
Import List.ListNotations.
From Coq Require Import Permutation.

Open Scope nat.
Open Scope list.

Module Type NL2STCCLOCKING
       (Import Ids   : IDS)
       (Import Op    : OPERATORS)
       (Import OpAux : OPERATORS_AUX   Op)
       (Import CStr  : COINDSTREAMS    Op OpAux)
       (Import IStr  : INDEXEDSTREAMS  Op OpAux)
       (Import CE    : COREEXPR    Ids Op OpAux      IStr)
       (Import NL    : NLUSTRE     Ids Op OpAux CStr IStr CE)
       (Import Stc   : STC         Ids Op OpAux      IStr CE)
       (Import Trans : TRANSLATION Ids Op                 CE.Syn NL.Syn Stc.Syn NL.Mem).

  Lemma translate_eqn_wc:
    forall G vars eq,
      wc_env vars ->
      NL.Clo.wc_equation G vars eq ->
      Forall (wc_trconstr (translate G) vars) (translate_eqn eq).
  Proof.
    inversion_clear 2 as [|??????? Find Ins Outs|];
      simpl; auto using Forall_cons.
    apply find_node_translate in Find as (?&?&?&?); subst.
    cases.
    - constructor.
      + do 2 (constructor; auto).
        eapply wc_env_var; eauto.
      + do 2 (econstructor; eauto).
    - do 2 (econstructor; eauto).
  Qed.

  Lemma gather_eqs_n_vars_wc:
    forall n G,
      Forall (NL.Clo.wc_equation G (idck (n_in n ++ n_vars n ++ n_out n))) (n_eqs n) ->
      Permutation (idck (fst (gather_eqs (n_eqs n))))
                  (idck
                     (fst
                        (partition
                           (fun x : positive * (type * clock) =>
                              PS.mem (fst x) (ps_from_list (map fst (fst (gather_eqs (n_eqs n))))))
                           (n_vars n)))).
  Proof.
    intros * WC.
    rewrite fst_partition_filter.
    apply NoDup_Permutation.
    - apply NoDupMembers_NoDup, NoDupMembers_idck, fst_NoDupMembers.
      rewrite fst_fst_gather_eqs_var_defined.
      pose proof (NoDup_var_defined_n_eqs n) as Hnodup;
        rewrite <-is_filtered_vars_defined in Hnodup.
      rewrite Permutation_app_comm in Hnodup; apply NoDup_app_weaken in Hnodup.
      rewrite Permutation_app_comm in Hnodup; apply NoDup_app_weaken in Hnodup.
      auto.
    - apply NoDupMembers_NoDup, fst_NoDupMembers.
      rewrite map_fst_idck, filter_mem_fst.
      apply nodup_filter.
      pose proof (n.(n_nodup)) as Hnodup.
      apply NoDupMembers_app_r, NoDupMembers_app_l in Hnodup.
      now apply fst_NoDupMembers.
    - intros (x, ck).
      setoid_rewrite ps_from_list_gather_eqs_memories.
      assert (forall x, In x (vars_defined (filter is_fby (n_eqs n))) ->
                   InMembers x (n_vars n)) as Spec
          by (intro; rewrite <-fst_partition_memories_var_defined, fst_partition_filter,
                     filter_mem_fst, filter_In, fst_InMembers; intuition).
      pose proof (filter_fst_idck (n_vars n)
                                  (fun x => PS.mem x (Mem.memories (n_eqs n)))) as E;
        setoid_rewrite E; clear E.
      setoid_rewrite filter_In.
      setoid_rewrite <-PSE.MP.Dec.F.mem_iff.
      unfold Mem.memories, gather_eqs in *.
      generalize (@nil (ident * ident)).
      induction (n_eqs n) as [|[]]; inversion_clear WC as [|?? WCeq]; simpl; intros; auto.
      + split; try contradiction.
        setoid_rewrite PSE.MP.Dec.F.empty_iff; intuition.
      + cases.
      + inversion_clear WCeq as [| |???? Hinc].
        rewrite In_fold_left_memory_eq, PSE.MP.Dec.F.add_iff, PSE.MP.Dec.F.empty_iff.
        split.
        *{ intros * Hin.
           unfold idck in Hin.
           apply in_map_iff in Hin as ((x', (c', ck')) & E & Hin); simpl in *; inv E.
           apply In_fst_fold_left_gather_eq in Hin as [Hin|Hin].
           - inversion_clear Hin as [E|]; try contradiction; inv E.
             intuition.
             assert (InMembers x (n_vars n)) by auto.
             pose proof (n_nodup n) as Hnodup.
             rewrite fst_NoDupMembers, 2 map_app, NoDup_swap, <- 2 map_app, <-fst_NoDupMembers in Hnodup.
             eapply NoDupMembers_app_InMembers, NotInMembers_app in Hnodup as (? & ?); eauto.
             rewrite 2 idck_app, 2 in_app in Hinc; destruct Hinc as [Hinc|[|Hinc]]; auto;
               apply In_InMembers in Hinc; rewrite InMembers_idck in Hinc; contradiction.
           - assert (In (x, ck) (idck (fst (fold_left gather_eq l ([], l0)))))
               as Hin' by (apply in_map_iff; eexists; intuition; eauto; simpl; auto).
             apply IHl in Hin'; intuition.
         }
         *{ intros * (Hin & [Mem|Mem]).
            - assert (In (x, ck) (idck (fst (fold_left gather_eq l ([], l0))))) as Hin'
                  by (apply IHl; auto; intros * Hin';
                      apply Spec; simpl; auto).
              unfold idck in Hin'; apply in_map_iff in Hin' as ((x', (c', ck')) & E & Hin'); simpl in *; inv E.
              apply in_map_iff; exists (x, (c', ck)); simpl.
              rewrite In_fst_fold_left_gather_eq; intuition.
            - destruct Mem as [E|]; try contradiction; inv E.
              apply in_map_iff; exists (x, (c0, c)); simpl.
              rewrite In_fst_fold_left_gather_eq; intuition.
              f_equal.
              assert (In (x, ck) (idck (n_in n ++ n_vars n ++ n_out n)))
                by (rewrite 2 idck_app, 2 in_app; auto).
              eapply NoDupMembers_det; eauto.
              apply NoDupMembers_idck, n_nodup.
          }
  Qed.

  Lemma wc_trconstrs_permutation:
    forall P vars vars' eqs,
      Permutation vars vars' ->
      Forall (wc_trconstr P vars) eqs ->
      Forall (wc_trconstr P vars') eqs.
  Proof.
    intros * E WC.
    eapply Forall_impl with (2 := WC); eauto.
    setoid_rewrite E; auto.
  Qed.

  Lemma translate_node_wc:
    forall G n,
      wc_node G n ->
      wc_system (translate G) (translate_node n).
  Proof.
    inversion_clear 1 as [? (?& Env & Heqs)].
    constructor; simpl; auto.
    assert (Permutation (idck
                           (n_in n ++
                                 snd
                                 (partition
                                    (fun x : positive * (type * clock) =>
                                       PS.mem (fst x) (ps_from_list (map fst (fst (gather_eqs (n_eqs n))))))
                                    (n_vars n)) ++ n_out n) ++ idck (fst (gather_eqs (n_eqs n))))
                        (idck (n_in n ++ n_vars n ++ n_out n))) as E.
    { repeat rewrite idck_app.
      rewrite Permutation_app_comm, Permutation_swap, gather_eqs_n_vars_wc,
      <-2 idck_app, app_assoc, <-permutation_partition, idck_app; eauto.
    }
    intuition.
    - now rewrite E.
    - apply Permutation_sym in E.
      eapply wc_trconstrs_permutation with (1 := E).
      unfold translate_eqns.
      clear - Heqs Env; induction (n_eqs n); simpl; inv Heqs; auto.
      apply Forall_app; split; auto.
      eapply translate_eqn_wc; eauto.
  Qed.

  Theorem translate_wc:
    forall G,
      wc_global G ->
      wc_program (translate G).
  Proof.
    intros * WC.
    induction G; simpl; inv WC; auto.
    constructor; auto.
    eapply translate_node_wc; eauto.
  Qed.

End NL2STCCLOCKING.

Module NL2StcClockingFun
       (Ids   : IDS)
       (Op    : OPERATORS)
       (OpAux : OPERATORS_AUX   Op)
       (CStr  : COINDSTREAMS    Op OpAux)
       (IStr  : INDEXEDSTREAMS  Op OpAux)
       (CE    : COREEXPR    Ids Op OpAux      IStr)
       (NL    : NLUSTRE     Ids Op OpAux CStr IStr CE)
       (Stc   : STC         Ids Op OpAux      IStr CE)
       (Trans : TRANSLATION Ids Op                 CE.Syn NL.Syn Stc.Syn NL.Mem)
<: NL2STCCLOCKING Ids Op OpAux CStr IStr CE NL Stc Trans.
  Include NL2STCCLOCKING Ids Op OpAux CStr IStr CE NL Stc Trans.
End NL2StcClockingFun.
