From Coq Require Import FSets.FMapPositive.
From Coq Require Import FSets.FMapFacts.
From Coq Require Import List.
From Coq Require Import Sorting.Permutation.

From Coq Require Import Setoid.
From Coq Require Import Relations.
From Coq Require Import Morphisms.

Import ListNotations.
From Coq Require MSets.MSets.
From Coq Require Export PArith.
(* Require Import Omega. *)
From Coq Require Import Classes.EquivDec.

From Velus Require Export Common.CommonTactics.
From Velus Require Export Common.CommonList.
From Velus Require Export ClockDefs.

Open Scope list.

(** * Common definitions *)

(** ** Finite sets and finite maps *)

(** These modules are used to manipulate identifiers. *)


Module PS := Coq.MSets.MSetPositive.PositiveSet.
Module PSP := MSetProperties.WPropertiesOn Pos PS.
Module PSF := MSetFacts.Facts PS.
Module PSE := MSetEqProperties.WEqPropertiesOn Pos PS.
Module PSdec := Coq.MSets.MSetDecide.WDecide PS.

Definition ident_eq_dec := Pos.eq_dec.
Definition ident_eqb := Pos.eqb.

Definition idents := list ident.

Instance: EqDec ident eq := { equiv_dec := ident_eq_dec }.

Implicit Type i j: ident.

(** ** Properties *)

Lemma not_or':
  forall A B, ~(A \/ B) <-> ~A /\ ~B.
Proof.
  split; intuition.
Qed.

Lemma flip_impl:
  forall {P Q : Prop},
    (P -> Q) ->
    ~Q ->
    ~P.
Proof. intros P Q HPQ HnQ HP. auto. Qed.

Lemma None_eq_dne:
  forall {A} (v : option A),
    ~(v <> None) <-> (v = None).
Proof.
  destruct v; intuition.
  exfalso. apply H; discriminate.
Qed.

(** *** About identifiers **)

Lemma ident_eqb_neq:
  forall x y, ident_eqb x y = false <-> x <> y.
Proof.
  unfold ident_eqb; apply Pos.eqb_neq.
Qed.

Lemma ident_eqb_eq:
  forall x y, ident_eqb x y = true <-> x = y.
Proof.
  unfold ident_eqb; apply Pos.eqb_eq.
Qed.

Lemma ident_eqb_refl:
  forall f, ident_eqb f f = true.
Proof.
  unfold ident_eqb; apply Pos.eqb_refl.
Qed.

Lemma ident_eq_sym:
  forall (x y: ident), x = y <-> y = x.
Proof.
  now intros; split; subst.
Qed.

Lemma decidable_eq_ident:
  forall (f g: ident),
    Decidable.decidable (f = g).
Proof.
  intros f g.
  unfold Decidable.decidable.
  setoid_rewrite <-ident_eqb_eq.
  destruct (ident_eqb f g); auto.
Qed.

Definition mem_assoc_ident {A} (x: ident): list (ident * A) -> bool :=
  existsb (fun y => ident_eqb (fst y) x).

Lemma mem_assoc_ident_false:
  forall {A} x xs (t: A),
    mem_assoc_ident x xs = false ->
    ~ In (x, t) xs.
Proof.
  intros ** Hin.
  apply Bool.not_true_iff_false in H.
  apply H.
  apply existsb_exists.
  exists (x, t); split; auto.
  apply ident_eqb_refl.
Qed.

Lemma mem_assoc_ident_true:
  forall {A} x xs,
    mem_assoc_ident x xs = true ->
    exists t: A, In (x, t) xs.
Proof.
  intros * Hin.
  unfold mem_assoc_ident in Hin; rewrite existsb_exists in Hin.
  destruct Hin as ((x', t) & ? & E).
  simpl in E; rewrite ident_eqb_eq in E; subst x'.
  eauto.
Qed.

Definition assoc_ident {A} (x: ident) (xs: list (ident * A)): option A :=
  match find (fun y => ident_eqb (fst y) x) xs with
  | Some (_, a) => Some a
  | None => None
  end.

Module Type IDS.
  Parameter self : ident.
  Parameter out  : ident.

  Parameter step  : ident.
  Parameter reset : ident.

  Parameter default : ident.

  Definition reserved : idents := [ self; out ].

  Definition methods  : idents := [ step; reset ].

  Axiom reserved_nodup: NoDup reserved.
  Axiom methods_nodup: NoDup methods.

  Axiom reset_not_step: reset <> step.

  Definition NotReserved {typ: Type} (xty: ident * typ) : Prop :=
    ~In (fst xty) reserved.

  Parameter prefix : ident -> ident -> ident.

  Parameter valid : ident -> Prop.

  Inductive prefixed: ident -> Prop :=
    prefixed_intro: forall pref id,
      prefixed (prefix pref id).

  Axiom valid_not_prefixed: forall x, valid x -> ~prefixed x.

  Definition ValidId {typ: Type} (xty: ident * typ) : Prop :=
    NotReserved xty /\ valid (fst xty).

End IDS.

Generalizable Variables A.

Lemma equiv_decb_equiv:
  forall `{EqDec A} (x y : A),
    equiv_decb x y = true <-> equiv x y.
Proof.
  intros. 
  split; intro; unfold equiv_decb in *;
    destruct (equiv_dec x y); intuition.
Qed.

Lemma nequiv_decb_false:
  forall {A} `{EqDec A} (x y: A),
    (x <>b y) = false <-> (x ==b y) = true.
Proof.
  unfold nequiv_decb, equiv_decb.
  intros. destruct (equiv_dec x y); intuition.
Qed.

Lemma equiv_decb_refl:
  forall `{EqDec A} (x: A),
    equiv_decb x x = true.
Proof.
  intros. now apply equiv_decb_equiv.
Qed.

Lemma not_equiv_decb_equiv:
  forall `{EqDec A} (x y: A),
    equiv_decb x y = false <-> ~(equiv x y).
Proof.
  split; intro Hne.
  - unfold equiv_decb in Hne.
    now destruct (equiv_dec x y).
  - unfold equiv_decb.
    destruct (equiv_dec x y); [|reflexivity].
    exfalso; now apply Hne.
Qed.

(** *** About Coq stdlib *)

Lemma pos_le_plus1:
  forall x, (x <= x + 1)%positive.
Proof.
  intros.
  rewrite Pos.add_1_r.
  apply Pos.lt_eq_cases.
  left; apply Pos.lt_succ_diag_r.
Qed.

Lemma pos_lt_plus1:
  forall x, (x < x + 1)%positive.
Proof.
  intros. rewrite Pos.add_1_r. apply Pos.lt_succ_diag_r.
Qed.

Lemma PS_In_In_mem_mem:
  forall x m n,
    PS.In x m <-> PS.In x n <-> PS.mem x m = PS.mem x n.
Proof.
  intros x m n.
  destruct (PS.mem x n) eqn:Heq.
  - rewrite <- PS.mem_spec. intuition.
  - rewrite <-PSE.MP.Dec.F.not_mem_iff.
    apply PSE.MP.Dec.F.not_mem_iff in Heq. intuition.
Qed.

Lemma not_None_is_Some:
  forall A (x : option A), x <> None <-> (exists v, x = Some v).
Proof.
  destruct x; intuition.
  exists a; reflexivity.
  discriminate.
  match goal with H:exists _, _ |- _ => destruct H end; discriminate.
Qed.

(* TODO: Why the hell can't I use <> ?!? *)
Corollary not_None_is_Some_Forall:
  forall {A} (xs: list (option A)),
    Forall (fun (v: option A) => ~ v = None) xs ->
    exists ys, xs = map Some ys.
Proof.
  induction 1 as [|?? E].
    - exists []; simpl; eauto.
    - rewrite not_None_is_Some in E. destruct E as (v, E).
      destruct IHForall as (vs & ?); subst.
      exists (v :: vs); simpl; eauto.
Qed.

Lemma not_Some_is_None:
  forall A (x : option A),  (forall v, x <> Some v) <-> x = None.
Proof.
  destruct x; intuition.
  - exfalso; now apply (H a).
  - discriminate.
  - discriminate.
Qed.


(** Lemmas on PositiveSets *)

Definition not_In_empty: forall x : ident, ~(PS.In x PS.empty) := PS.empty_spec.

Ltac not_In_empty :=
  match goal with H:PS.In _ PS.empty |- _ => now apply not_In_empty in H end.

Lemma not_not_in:
  forall x A, ~~PS.In x A <-> PS.In x A.
Proof.
  split; intro HH.
  now apply Decidable.not_not in HH; intuition.
  now apply Decidable.not_not; intuition.
Qed.

Lemma PS_not_inter:
  forall s t x,
    ~PS.In x (PS.inter s t) <-> ~PS.In x s \/ ~PS.In x t.
Proof.
  setoid_rewrite PS.inter_spec.
  split; intro HH.
  apply Decidable.not_and in HH; auto using PSdec.MSetDecideAuxiliary.dec_In.
  intuition.
Qed.

Lemma PS_union_diff_same:
  forall s t,
    PS.Equal (PS.union (PS.diff s t) t) (PS.union s t).
Proof.
  unfold PS.Equal. setoid_rewrite PS.union_spec.
  setoid_rewrite PS.diff_spec.
  split; intro HH. now intuition.
  destruct HH. now destruct (PSP.In_dec a t); intuition.
  now intuition.
Qed.

Lemma PS_not_union:
  forall s t x,
    ~PS.In x (PS.union s t) <-> ~PS.In x s /\ ~PS.In x t.
Proof.
  setoid_rewrite PS.union_spec.
  split; intro HH; intuition.
Qed.

Lemma PS_not_diff:
  forall s t x,
    ~PS.In x (PS.diff s t) <-> ~PS.In x s \/ PS.In x (PS.inter s t).
Proof.
  setoid_rewrite PS.inter_spec.
  setoid_rewrite PS.diff_spec.
  split; intro HH.
  - apply Decidable.not_and in HH; auto using PSdec.MSetDecideAuxiliary.dec_In.
    destruct HH as [HH|HH]; auto.
    apply Decidable.not_not in HH; auto using PSdec.MSetDecideAuxiliary.dec_In.
    destruct (PSP.In_dec x s); auto.
  - destruct 1; destruct HH as [|[? ?]]; auto.
Qed.

Lemma PS_disjoint1:
  forall s1 s2,
    PS.Empty (PS.inter s1 s2) ->
    forall x, PS.In x s1 -> ~PS.In x s2.
Proof.
  intros s1 s2 Hdj x Hin1 Hin2.
  apply (Hdj x). rewrite PS.inter_spec; auto.
Qed.

Lemma PS_disjoint2:
  forall s1 s2,
    PS.Empty (PS.inter s1 s2) ->
    forall x, PS.In x s2 -> ~PS.In x s1.
Proof.
  setoid_rewrite PSP.inter_sym. eauto using PS_disjoint1.
Qed.

Lemma PS_diff_inter_same:
  forall A B C,
    PS.Equal (PS.diff (PS.inter A C) (PS.inter B C))
             (PS.inter (PS.diff A B) C).
Proof.
  intros A B C x. split; intro HH.
  - apply PS.diff_spec in HH.
    destruct HH as (HAC & HBC).
    apply PSP.FM.inter_3; [apply PSP.FM.diff_3|];
      eauto using PSF.inter_1, PSF.inter_2, PSF.inter_3.
  - apply PS.inter_spec in HH.
    destruct HH as (HAB & HC).
    apply PS.diff_spec in HAB.
    destruct HAB as (HA & HB).
    apply PSP.FM.diff_3; [apply PSP.FM.inter_3|];
      eauto using PSF.inter_1, PSF.inter_2, PSF.inter_3.
Qed.

Lemma PS_inter_union_dist:
  forall A B C D,
    PS.Equal (PS.inter (PS.union A B) (PS.union C D))
             (PS.union (PS.inter A C)
                       (PS.union (PS.inter A D)
                                 (PS.union (PS.inter B C)
                                           (PS.inter B D)))).
Proof.
  intros A B C D.
  split; intro HH.
  - rewrite PS.inter_spec in HH.
    setoid_rewrite PS.union_spec in HH.
    destruct HH as [[H1|H1] [H2|H2]]; intuition.
  - repeat setoid_rewrite PS.union_spec in HH.
    repeat setoid_rewrite PS.inter_spec in HH.
    destruct HH as [[HH1 HH2]|[[HH1 HH2]|[[HH1 HH2]|[HH1 HH2]]]];
      intuition.
Qed.

Lemma PS_inter_inter_same:
  forall A B C,
    PS.Equal (PS.inter (PS.inter A C) (PS.inter B C))
             (PS.inter (PS.inter A B) C).
Proof.
  split; intro HH; repeat rewrite PS.inter_spec in *; intuition.
Qed.

Lemma PS_For_all_Forall:
  forall P s,
    PS.For_all P s <-> Forall P (PS.elements s).
Proof.
  split; intro HH.
  - apply Forall_forall.
    intros x Hin. apply HH.
    apply PSF.elements_iff; auto.
  - intros x Hin.
    rewrite Forall_forall in HH; apply HH.
    apply PSF.elements_iff, SetoidList.InA_alt in Hin.
    destruct Hin as (? & ? & ?); subst; auto.
Qed.

Lemma PS_not_in_diff:
  forall x s t,
    ~PS.In x t ->
    ~PS.In x (PS.diff s t) ->
    ~PS.In x s.
Proof.
  setoid_rewrite PS.diff_spec. intuition.
Qed.

Lemma PS_For_all_empty:
  forall P,
    PS.For_all P PS.empty.
Proof.
  setoid_rewrite PS_For_all_Forall.
  setoid_rewrite PSP.elements_empty. auto.
Qed.

Lemma PS_In_Forall:
  forall P S,
    PS.For_all P S ->
    forall x, PS.In x S -> P x.
Proof.
  intros P S Hfa x Hin.
  apply PS_For_all_Forall in Hfa.
  apply PSP.FM.elements_iff in Hin.
  eapply Forall_forall in Hfa; eauto.
  apply SetoidList.InA_alt in Hin as (y & Heq & ?).
  subst; auto.
Qed.

Lemma PS_For_all_sub:
  forall P S T,
    PS.For_all P S ->
    (forall x, PS.In x T -> PS.In x S) ->
    PS.For_all P T.
Proof.
  intros P S T HP Hsub x HT.
  apply Hsub in HT.
  apply PS_In_Forall with (1:=HP) (2:=HT).
Qed.

Lemma PS_For_all_diff:
  forall P S T,
    PS.For_all P S ->
    PS.For_all P (PS.diff S T).
Proof.
  intros P S T HP. apply PS_For_all_sub with (1:=HP).
  intros x HH; apply PS.diff_spec in HH; intuition.
Qed.

Lemma PS_For_all_inter:
  forall P S T,
    PS.For_all P S ->
    PS.For_all P (PS.inter S T).
Proof.
  intros P S T HP. apply PS_For_all_sub with (1:=HP).
  intros x HH; apply PS.inter_spec in HH; intuition.
Qed.

Lemma PS_For_all_union:
  forall P S T,
    PS.For_all P S ->
    PS.For_all P T ->
    PS.For_all P (PS.union S T).
Proof.
  intros P S T HS HT x HH.
  apply PS.union_spec in HH as [HH|HH]; intuition.
Qed.

Lemma PS_For_all_impl_In:
  forall (P Q : PS.elt -> Prop) S,
    PS.For_all P S ->
    (forall x, PS.In x S -> P x -> Q x) ->
    PS.For_all Q S.
Proof.
  intros P Q S HP HPQ x HS.
  apply PS_In_Forall with (2:=HS) in HP; auto.
Qed.

Instance PS_For_all_Equals_Proper:
  Proper (pointwise_relation positive iff ==> PS.Equal ==> iff) PS.For_all.
Proof.
  intros P Q Hpw S T Heq.
  split; intros HH x Hx; apply PS_In_Forall with (x:=x) in HH;
    try apply Hpw; auto.
  now rewrite Heq. now rewrite Heq in Hx.
Qed.

Lemma PS_For_all_add:
  forall P a S,
    PS.For_all P (PS.add a S) <-> (P a /\ PS.For_all P S).
Proof.
  split.
  - intro HH. split.
    + apply PS_In_Forall with (1:=HH).
      now apply PS.add_spec; left.
    + apply PS_For_all_sub with (1:=HH).
      intros; apply PS.add_spec; auto.
  - intros (HPa, HPS) x Hadd.
    apply PS.add_spec in Hadd as [HH|HH]; subst; auto.
Qed.

Lemma In_PS_elements:
  forall x s,
    In x (PS.elements s) <-> PS.In x s.
Proof.
  intros x s. split; intro HH.
  - now apply (SetoidList.In_InA Pos.eq_equiv), PSF.elements_2 in HH.
  - cut (exists z, eq x z /\ In z (PS.elements s)).
    + intros (? & ? & ?); subst; auto.
    + now apply SetoidList.InA_alt, PSF.elements_1.
Qed.

Lemma Permutation_elements_add:
  forall xs x s,
    Permutation (PS.elements s) xs ->
    ~PS.In x s ->
    Permutation (PS.elements (PS.add x s)) (x::xs).
Proof.
  intros * Hperm Hnin.
  setoid_rewrite <- Hperm; clear Hperm.
  apply NoDup_Permutation.
  - apply NoDup_NoDupA, PS.elements_spec2w.
  - constructor; [|now apply NoDup_NoDupA, PS.elements_spec2w].
    setoid_rewrite PSF.elements_iff in Hnin; auto.
  - clear. intro z.
    setoid_rewrite In_PS_elements.
    setoid_rewrite PS.add_spec.
    split; intros [HH|HH]; subst; auto.
    + now constructor.
    + now constructor 2; apply In_PS_elements.
    + apply In_PS_elements in HH; auto.
Qed.

Add Morphism PS.elements
    with signature PS.Equal ==> @Permutation positive
        as PS_elements_Equal.
Proof.
  intros x y Heq.
  apply NoDup_Permutation;
    (try apply NoDup_NoDupA, PS.elements_spec2w).
  now setoid_rewrite In_PS_elements.
Qed.

Lemma Permutation_PS_elements_of_list:
  forall xs,
    NoDup xs ->
    Permutation (PS.elements (PSP.of_list xs)) xs.
Proof.
  induction xs as [|x xs IH]; auto.
  rewrite NoDup_cons'. intros (Hxni & Hnd).
  simpl. specialize (IH Hnd).
  setoid_rewrite (Permutation_elements_add xs); auto.
  rewrite PSP.of_list_1.
  rewrite SetoidList.InA_alt.
  intros (y & Hxy & Hyin); subst; auto.
Qed.

Definition ps_adds (xs: list positive) (s: PS.t) :=
  fold_left (fun s x => PS.add x s) xs s.

Definition ps_from_list (l: list positive) : PS.t :=
  ps_adds l PS.empty.

Lemma ps_adds_spec:
  forall s xs y,
    PS.In y (ps_adds xs s) <-> In y xs \/ PS.In y s.
Proof.
  intros s xs y. revert s.
  induction xs; intro s; simpl.
  - intuition.
  - rewrite IHxs. rewrite PS.add_spec. intuition.
Qed.

Instance eq_equiv : Equivalence PS.eq.
Proof. firstorder. Qed.

Instance ps_adds_Proper (xs: idents) :
  Proper (PS.eq ==> PS.eq) (ps_adds xs).
Proof.
  induction xs as [|x xs IH]; intros S S' Heq; [exact Heq|].
  assert (PS.eq (PS.add x S) (PS.add x S')) as Heq'
      by (rewrite Heq; reflexivity).
  simpl; rewrite Heq'; reflexivity.
Qed.

Lemma add_ps_from_list_cons:
  forall xs x,
    PS.eq (PS.add x (ps_from_list xs))
          (ps_from_list (x :: xs)).
Proof.
  intros; unfold ps_from_list; simpl.
  generalize PS.empty as S.
  induction xs as [|y xs IH]; [ reflexivity | ].
  intro S; simpl; rewrite IH; rewrite PSP.add_add; reflexivity.
Qed.

Lemma ps_from_list_In:
  forall xs x,
    PS.In x (ps_from_list xs) <-> In x xs.
Proof.
  induction xs; simpl.
  - split; try contradiction; apply not_In_empty.
  - split; intros * Hin.
    + rewrite <-IHxs.
      rewrite <-add_ps_from_list_cons in Hin.
      apply PSE.MP.Dec.F.add_iff in Hin as []; auto.
    + rewrite <-IHxs in Hin; rewrite <-add_ps_from_list_cons, PS.add_spec; intuition.
Qed.

Instance ps_from_list_Permutation:
  Proper (@Permutation.Permutation ident ==> fun xs xs' => forall x, PS.In x xs -> PS.In x xs')
         ps_from_list.
Proof.
  intros * ?? E ? Hin.
  apply ps_from_list_In; apply ps_from_list_In in Hin.
  now rewrite <-E.
Qed.

Lemma ps_adds_In:
  forall x xs s,
    PS.In x (ps_adds xs s) ->
    ~PS.In x s ->
    In x xs.
Proof.
  induction xs as [|x' xs IH]. now intuition.
  simpl. intros s Hin Hnin.
  apply ps_adds_spec in Hin.
  rewrite PSF.add_iff in Hin.
  destruct Hin as [|[Hin|Hin]]; intuition.
Qed.

Lemma Permutation_PS_elements_ps_adds:
  forall xs S,
    NoDup xs ->
    Forall (fun x => ~PS.In x S) xs ->
    Permutation (PS.elements (ps_adds xs S)) (xs ++ PS.elements S).
Proof.
  induction xs as [|x xs IH]; auto.
  intros S Hnd Hni.
  apply NoDup_Permutation.
  - apply NoDup_NoDupA, PS.elements_spec2w.
  - apply NoDup_app'; auto.
    apply NoDup_NoDupA, PS.elements_spec2w.
    apply Forall_impl_In with (2:=Hni).
    setoid_rewrite In_PS_elements; auto.
  - apply NoDup_cons' in Hnd as (Hnxs & Hnd).
    apply Forall_cons2 in Hni as (HnS & Hni).
    simpl; intro y.
    setoid_rewrite (IH _ Hnd).
    + repeat rewrite in_app.
      repeat rewrite In_PS_elements.
      rewrite PS.add_spec.
      split; intros [HH|[HH|HH]]; auto.
    + apply Forall_impl_In with (2:=Hni).
      intros z Hzxs Hnzs HzxS.
      apply PSF.add_3 in HzxS; auto.
      intro; subst; auto.
Qed.

Lemma Subset_ps_adds:
  forall xs S S',
    PS.Subset S S' ->
    PS.Subset (ps_adds xs S) (ps_adds xs S').
Proof.
  induction xs as [|x xs IH]; auto.
  intros S S' Hsub. simpl. apply IH.
  rewrite Hsub. reflexivity.
Qed.

Definition ps_removes (xs: list positive) (s: PS.t)
  := fold_left (fun s x => PS.remove x s) xs s.

Lemma ps_removes_spec: forall s xs y,
    PS.In y (ps_removes xs s) <-> ~In y xs /\ PS.In y s.
Proof.
  intros s xs y. revert s.
  induction xs; intro s; simpl.
  - intuition.
  - rewrite IHxs. rewrite PS.remove_spec. intuition.
Qed.

Lemma PS_For_all_ps_adds:
  forall P xs S,
    PS.For_all P (ps_adds xs S) <-> (Forall P xs /\ PS.For_all P S).
Proof.
  induction xs. now intuition.
  simpl. setoid_rewrite IHxs.
  setoid_rewrite Forall_cons2.
  setoid_rewrite PS_For_all_add.
  intuition.
Qed.

Lemma ps_adds_of_list:
  forall xs,
    PS.Equal (ps_adds xs PS.empty) (PSP.of_list xs).
Proof.
  intros xs x. rewrite ps_adds_spec, PSP.of_list_1; split.
  -intros [Hin|Hin]; auto. now apply not_In_empty in Hin.
  - intro Hin. apply SetoidList.InA_alt in Hin as (y & Hy & Hin); subst; auto.
Qed.

(** types and clocks *)

Section TypesAndClocks.

  Context {type clock : Type}.

  (* A Lustre variable is declared with a type and a clock.
     In the abstract syntax, a declaration is represented as a triple:
     (x, (ty, ck)) : ident * (type * clock)

     And nodes include lists of triples for lists of declarations.
     The following definitions and lemmas facilitate working with such
     values. *)

  Definition dty (x : ident * (type * clock)) : type := fst (snd x).
  Definition dck (x : ident * (type * clock)) : clock := snd (snd x).

  Definition idty : list (ident * (type * clock)) -> list (ident * type) :=
    map (fun xtc => (fst xtc, fst (snd xtc))).

  Definition idck : list (ident * (type * clock)) -> list (ident * clock) :=
    map (fun xtc => (fst xtc, snd (snd xtc))).

  (* idty *)

  Lemma idty_app:
    forall xs ys,
      idty (xs ++ ys) = idty xs ++ idty ys.
  Proof.
    induction xs; auto.
    simpl; intro; now rewrite IHxs.
  Qed.

  Lemma InMembers_idty:
    forall x xs,
      InMembers x (idty xs) <-> InMembers x xs.
  Proof.
    induction xs as [|x' xs]; split; auto; intro HH;
      destruct x' as (x' & tyck); simpl.
    - rewrite <-IHxs; destruct HH; auto.
    - rewrite IHxs. destruct HH; auto.
  Qed.

  Lemma NoDupMembers_idty:
    forall xs,
      NoDupMembers (idty xs) <-> NoDupMembers xs.
  Proof.
    induction xs as [|x xs]; split; inversion_clear 1;
      eauto using NoDupMembers_nil; destruct x as (x & tyck); simpl in *;
      constructor; try rewrite InMembers_idty in *;
      try rewrite IHxs in *; auto.
  Qed.

  Lemma map_fst_idty:
    forall xs,
      map fst (idty xs) = map fst xs.
  Proof.
    induction xs; simpl; try rewrite IHxs; auto.
  Qed.

  Lemma length_idty:
    forall xs,
      length (idty xs) = length xs.
  Proof.
    induction xs as [|x xs]; auto.
    destruct x; simpl. now rewrite IHxs.
  Qed.

  Lemma In_idty_exists:
    forall x (ty : type) xs,
      In (x, ty) (idty xs) <-> exists (ck: clock), In (x, (ty, ck)) xs.
  Proof.
    induction xs as [|x' xs].
    - split; inversion_clear 1. inv H0.
    - split.
      + inversion_clear 1 as [HH|HH];
          destruct x' as (x' & ty' & ck'); simpl in *.
        * inv HH; eauto.
        * apply IHxs in HH; destruct HH; eauto.
      + destruct 1 as (ck & HH).
        inversion_clear HH as [Hin|Hin].
        * subst; simpl; auto.
        * constructor 2; apply IHxs; eauto.
  Qed.

  Global Instance idty_Permutation_Proper:
    Proper (@Permutation (ident * (type * clock))
            ==> @Permutation (ident * type)) idty.
  Proof.
    intros xs ys Hperm.
    unfold idty. rewrite Hperm.
    reflexivity.
  Qed.

  (* idck *)

  Lemma idck_app:
    forall xs ys,
      idck (xs ++ ys) = idck xs ++ idck ys.
  Proof.
    induction xs; auto.
    simpl; intro; now rewrite IHxs.
  Qed.

  Lemma InMembers_idck:
    forall x xs,
      InMembers x (idck xs) <-> InMembers x xs.
  Proof.
    induction xs as [|x' xs]; split; auto; intro HH;
      destruct x' as (x' & tyck); simpl.
    - rewrite <-IHxs; destruct HH; auto.
    - rewrite IHxs. destruct HH; auto.
  Qed.

  Lemma NoDupMembers_idck:
    forall xs,
      NoDupMembers (idck xs) <-> NoDupMembers xs.
  Proof.
    induction xs as [|x xs]; split; inversion_clear 1;
      eauto using NoDupMembers_nil; destruct x as (x & tyck); simpl in *;
      constructor; try rewrite InMembers_idck in *;
      try rewrite IHxs in *; auto.
  Qed.

  Lemma map_fst_idck:
    forall xs,
      map fst (idck xs) = map fst xs.
  Proof.
    induction xs; simpl; try rewrite IHxs; auto.
  Qed.

  Lemma length_idck:
    forall xs,
      length (idck xs) = length xs.
  Proof.
    induction xs as [|x xs]; auto.
    destruct x; simpl. now rewrite IHxs.
  Qed.

  Lemma In_idck_exists:
    forall x (ck : clock) xs,
      In (x, ck) (idck xs) <-> exists (ty: type), In (x, (ty, ck)) xs.
  Proof.
    induction xs as [|x' xs].
    - split; inversion_clear 1. inv H0.
    - split.
      + inversion_clear 1 as [HH|HH];
          destruct x' as (x' & ty' & ck'); simpl in *.
        * inv HH; eauto.
        * apply IHxs in HH; destruct HH; eauto.
      + destruct 1 as (ty & HH).
        inversion_clear HH as [Hin|Hin].
        * subst; simpl; auto.
        * constructor 2; apply IHxs; eauto.
  Qed.

  Global Instance idck_Permutation_Proper:
    Proper (Permutation (A:=(ident * (type * clock)))
            ==> Permutation (A:=(ident * clock))) idck.
  Proof.
    intros xs ys Hperm.
    unfold idck. rewrite Hperm.
    reflexivity.
  Qed.

  Lemma filter_fst_idck:
    forall (xs: list (ident * (type * clock))) P,
      idck (filter (fun x => P (fst x)) xs) = filter (fun x => P (fst x)) (idck xs).
  Proof.
    induction xs; simpl; intros; auto.
    cases; simpl; now rewrite IHxs.
  Qed.

End TypesAndClocks.

(** Sets and maps of identifiers as efficient list lookups *)

Section Ps_From_Fo_List.

  Context {A : Type} (f: A -> option ident).

  Definition ps_from_fo_list' (xs: list A) (s: PS.t) : PS.t :=
    fold_left (fun s x=> match f x with
                      | None => s
                      | Some i => PS.add i s
                      end) xs s.

  Definition ps_from_fo_list (xs: list A) : PS.t :=
    ps_from_fo_list' xs PS.empty.

  Lemma In_ps_from_fo_list':
    forall x xs s,
      PS.In x (ps_from_fo_list' xs s) ->
      PS.In x s \/ In (Some x) (map f xs).
  Proof.
    induction xs as [|x' xs IH]; simpl; auto.
    intros s Hin.
    destruct (f x'); apply IH in Hin as [Hin|Hin]; auto.
    destruct (ident_eq_dec i x); subst; auto.
    rewrite PSF.add_neq_iff in Hin; auto.
  Qed.

End Ps_From_Fo_List.

Lemma In_of_list_InMembers:
  forall {A} x (xs : list (ident * A)),
    PS.In x (PSP.of_list (map fst xs)) <-> InMembers x xs.
Proof.
  split; intros Hin.
  - apply PSP.of_list_1, SetoidList.InA_alt in Hin as (y & Heq & Hin); subst y.
    now apply fst_InMembers.
  - apply PSP.of_list_1, SetoidList.InA_alt.
    apply fst_InMembers in Hin. eauto.
Qed.

(** Useful functions on lists of options *)

Section OptionLists.

  Context {A B : Type}.

  Definition omap (f : A -> option B) (xs : list A) : option (list B) :=
    List.fold_right (fun x ys => match f x, ys with
                              | Some y, Some ys => Some (y :: ys)
                              | _, _ => None
                              end) (Some []) xs.

  Definition ofold_right (f : A -> B -> option B) (acc : option B) (xs : list A)
    : option B :=
    fold_right (fun x acc => match acc with
                          | Some acc => f x acc
                          | None => None
                          end) acc xs.

End OptionLists.

(** Lift relations into the option type *)

Section ORel.

  Context {A : Type}
          (R : relation A).

  Definition orel: relation (option A) :=
    fun sx sy => (sx = None /\ sy = None)
              \/ (exists x y, sx = Some x /\ sy = Some y /\ R x y).

  Global Instance orel_refl `{RR : Reflexive A R} : Reflexive orel.
  Proof.
    intro sx.
    unfold orel.
    destruct sx; auto.
    right; eauto.
  Qed.
  
  Global Instance orel_trans `{RT : Transitive A R} : Transitive orel.
  Proof.
    unfold orel.
    intros sx sy sz [(XY1, XY2)|(x & y & XY1 & XY2 & XY3)]
           [(YZ1, YZ2)|(w & z & YZ1 & YZ2 & YZ3)]; subst; auto;
      try discriminate.
    inv YZ1. eapply RT in XY3. eapply XY3 in YZ3.
    right; eauto.
  Qed.

  Global Instance orel_sym `{RS : Symmetric A R} : Symmetric orel.
  Proof.
    unfold orel.
    intros sx sy [(XY1, XY2)|(x & y & XY1 & XY2 & XY3)]; subst; auto.
    symmetry in XY3. right; eauto.
  Qed.
  
  Global Instance orel_equiv `{Equivalence A R} : Equivalence orel.
  Proof (Build_Equivalence orel orel_refl orel_sym orel_trans).

  Global Instance orel_preord `{PreOrder A R} : PreOrder orel.
  Proof (Build_PreOrder orel orel_refl orel_trans).

  Global Instance orel_Some_Proper: Proper (R ==> orel) Some.
  Proof.
    intros x y Rxy. right. eauto.
  Qed.

End ORel.
