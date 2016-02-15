Require Import Coq.FSets.FMapPositive.
Require Import Nelist.
Require Import List.
Require Coq.MSets.MSets.
Require Export PArith.
Require Import Omega.


(** * Common definitions *)

Module PS := Coq.MSets.MSetPositive.PositiveSet.
Module PSP := MSetProperties.WPropertiesOn Pos PS.
Module PSF := MSetFacts.Facts PS.

Module PM := Coq.FSets.FMapPositive.PositiveMap.

Definition ident := positive.
Definition ident_eq_dec := Pos.eq_dec.
Definition ident_eqb := Pos.eqb.

Implicit Type i j: ident.

(* The basic types supported by Rustre *)
Inductive base_type := Tint | Tbool.
Inductive const : Set :=
| Cint : BinInt.Z -> const
| Cbool : bool -> const.

Inductive arity :=
  | Tout (t_out : base_type)
  | Tcons (t_in : base_type) (arr : arity).

(* Our own version of RelationClasses.arrows interpreting the arity *)
Definition base_interp t :=
  match t with
    | Tint => BinInt.Z
    | Tbool => bool
  end.

Fixpoint arrows (l : arity) : Set :=
  match l with
    | Tout t => base_interp t
    | Tcons A ar => base_interp A -> arrows ar
  end.

(* The set of external operators. idea: operator = sigT arrows but we want decidable equality *)
Definition operator := sigT arrows.
Definition get_arity : operator -> arity := @projT1 _ _.
Definition get_interp : forall op : operator, arrows (get_arity op) := @projT2 _ _.

Lemma arity_dec : forall ar1 ar2 : arity, {ar1 = ar2} + {ar1 <> ar2}.
Proof. do 2 decide equality. Qed.

(* Must be postulated because we do not have decidable equality on function types.
   Can be avoided, if we add an id field with a decidable equality. *)
Axiom op_dec : forall op1 op2 : operator, {op1 = op2} + {op1 <> op2}.

Example plus : operator.
exists (Tcons Tint (Tcons Tint (Tout Tint))).
exact BinInt.Z.add.
Defined.

(** * Common (and preliminary) results **)

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

Lemma In_dec:
  forall x S, {PS.In x S}+{~PS.In x S}.
Proof.
  intros i m; unfold PS.In; case (PS.mem i m); auto.
Qed.

Definition const_eqb (c1: const) (c2: const) : bool :=
  match c1, c2 with
  | Cint z1, Cint z2 => BinInt.Z.eqb z1 z2
  | Cbool b1, Cbool b2 => Bool.eqb b1 b2
  | _, _ => false
  end.

Lemma const_eqb_eq:
  forall (c1 c2: const),
    const_eqb c1 c2 = true <-> c1 = c2.
Proof.
  split.
  - destruct c1, c2; simpl; intro H; try discriminate.
    + apply BinInt.Z.eqb_eq in H; rewrite H; reflexivity.
    + apply Bool.eqb_prop in H; rewrite H; reflexivity.
  - destruct c1, c2; simpl; intro H0; try discriminate H0.
    + injection H0.
      intro H1; rewrite H1.
      destruct z, z0; simpl;
      (reflexivity || discriminate || (apply Pos.eqb_eq; reflexivity)).
    + injection H0.
      intro H1; rewrite H1.
      destruct b, b0; simpl; try reflexivity.
Qed.

Lemma const_eq_dec: forall (c1 c2: const), {c1=c2}+{c1<>c2}.
Proof.
  intros c1 c2.
  destruct (const_eqb c1 c2) eqn:Heq; [left|right].
  apply const_eqb_eq; assumption.
  intro H; apply const_eqb_eq in H.
  rewrite Heq in H; discriminate.
Qed.

Lemma Forall_cons2:
  forall A P (x: A) l,
    List.Forall P (x :: l) <-> P x /\ List.Forall P l.
Proof. intros; split; inversion_clear 1; auto. Qed.

Lemma pm_in_dec: forall A i m, PM.In (A:=A) i m \/ ~PM.In (A:=A) i m.
Proof.
  unfold PM.In, PM.MapsTo.
  intros A i m.
  case (PM.find i m).
  eauto.
  right; intro; destruct H; discriminate H.
Qed.

Lemma Some_injection:
  forall A (x:A) (y:A), x = y <-> Some x = Some y.
Proof.
  split; intro H; [rewrite H|injection H]; auto.
Qed.

(* TODO: Is there a more direct way to negate PS.mem_spec?
         I.e., without creating a distinct lemma. *)
Lemma mem_spec_false:
  forall s x, PS.mem x s = false <-> ~PS.In x s.
Proof.
  split.
  intros Hmem Hin.
  apply PS.mem_spec in Hin.
  rewrite Hin in Hmem.
  discriminate.
  intro Hnin.
  apply Bool.not_true_iff_false.
  intro Hnmem.
  rewrite PS.mem_spec in Hnmem.
  contradiction.
Qed.

Import List.ListNotations.
Open Scope list_scope.

Lemma List_shift_first:
  forall (A:Set) ll (x : A) lr,
    ll ++ (x :: lr) = (ll ++ [x]) ++ lr.
Proof.
  induction ll as [|? ? IH]; [auto|intros].
  rewrite <- List.app_comm_cons.
  rewrite IH.
  now do 2 rewrite List.app_comm_cons.
Qed.

Lemma List_shift_away:
  forall (A:Set) alleqs (eq : A) eqs,
    (exists oeqs, alleqs = oeqs ++ (eq :: eqs))
    -> exists oeqs', alleqs = oeqs' ++ eqs.
Proof.
  intros A alleqs eq eqs Hall.
  destruct Hall as [oeqs Hall].
  exists (oeqs ++ [eq]).
  rewrite Hall.
  now rewrite List_shift_first.
Qed.

Lemma Forall_app:
  forall A (P: A -> Prop) ll rr,
    Forall P (ll ++ rr) <-> (Forall P ll /\ Forall P rr).
Proof.
  intros A P ll rr.
  induction ll as [|x ll IH]; [intuition|].
  rewrite Forall_cons2.
  rewrite and_assoc.
  rewrite <-IH.
  rewrite <-List.app_comm_cons.
  now rewrite Forall_cons2.
Qed.

Lemma Exists_app:
  forall A (P: A -> Prop) ll rr,
    Exists P rr
    -> Exists P (ll ++ rr).
Proof.
  intros A P ll rr Hex.
  induction ll as [|x ll IH]; [intuition|].
  rewrite <-List.app_comm_cons.
  constructor 2.
  exact IH.
Qed.

Lemma Forall_Forall:
  forall A P Q (xs : list A),
    Forall P xs -> Forall Q xs -> Forall (fun x=>P x /\ Q x) xs.
Proof.
  induction xs as [|x xs IH]; [now constructor|].
  intros HPs HQs.
  inversion_clear HPs as [|? ? HP HPs'].
  inversion_clear HQs as [|? ? HQ HQs'].
  intuition.
Qed.

Lemma Forall_Exists:
  forall A (P Q: A -> Prop) xs,
    Forall P xs
    -> Exists Q xs
    -> Exists (fun x=>P x /\ Q x) xs.
Proof.
  induction xs as [|x xs IH]; [now inversion 2|].
  intros Ha He.
  inversion_clear Ha.
  inversion_clear He; auto.
Qed.

Lemma not_None_is_Some:
  forall A (x : option A), x <> None <-> (exists v, x = Some v).
Proof.
  destruct x; intuition.
  exists a; reflexivity.
  discriminate.
  match goal with H:exists _, _ |- _ => destruct H end; discriminate.
Qed.

Definition not_In_empty: forall x : ident, ~(PS.In x PS.empty) := PS.empty_spec.

Ltac not_In_empty :=
  match goal with H:PS.In _ PS.empty |- _ => now apply not_In_empty in H end.

Lemma map_eq_cons : forall {A B} (f : A -> B) l y l',
  map f l = y :: l' -> exists x l'', l = x :: l'' /\ f x = y.
Proof.
intros A B f l y l' Hmap. destruct l; simpl in Hmap.
- discriminate.
- inversion_clear Hmap. eauto.
Qed.

(* A constant list of the same size *)
Definition alls {A B} c (l : nelist A) : nelist B := Nelist.map (fun _ => c) l.


Definition op_eqb op1 op2 := if op_dec op1 op2 then true else false.

Lemma op_eqb_true_iff : forall op1 op2, op_eqb op1 op2 = true <-> op1 = op2.
Proof. intros op1 op2. unfold op_eqb. destruct (op_dec op1 op2); intuition discriminate. Qed.

Lemma op_eqb_false_iff : forall op1 op2, op_eqb op1 op2 = false <-> op1 <> op2.
Proof. intros op1 op2. unfold op_eqb. destruct (op_dec op1 op2); intuition discriminate. Qed.

Open Scope bool_scope.

Fixpoint forall2b {A B} (f : A -> B -> bool) l1 l2 :=
  match l1, l2 with
    | nil, nil => true
    | e1 :: l1, e2 :: l2 => f e1 e2 && forall2b f l1 l2
    | _, _ => false
  end.

Lemma Forall2_forall2 : forall {A B : Type} P l1 l2,
  Forall2 P l1 l2 <-> length l1 = length l2 /\
                      forall (a : A) (b : B) n x1 x2, n < length l1 -> nth n l1 a = x1 -> nth n l2 b = x2 -> P x1 x2.
Proof.
intros A B P l1. induction l1; intro l2.
* split; intro H.
  + inversion_clear H. split; simpl; auto. intros. omega.
  + destruct H as [H _]. destruct l2; try discriminate. constructor.
* split; intro H.
  + inversion_clear H. rewrite IHl1 in H1. destruct H1. split; simpl; auto.
    intros. destruct n; subst; trivial. eapply H1; eauto. omega.
  + destruct H as [Hlen H].
    destruct l2; simpl in Hlen; try discriminate. constructor.
    apply (H a b 0); trivial; simpl; try omega.
    rewrite IHl1. split; try omega.
    intros. eapply (H a0 b0 (S n)); simpl; eauto. simpl; omega.
Qed.

Corollary Forall2_length : forall {A B} (P : A -> B -> Prop) l1 l2,
  Forall2 P l1 l2 -> length l1 = length l2.
Proof. intros * Hall. rewrite Forall2_forall2 in Hall. now destruct Hall. Qed.

(** ** Results about arities *)

(* length function *)
Fixpoint nb_args (ar : arity) :=
  match ar with
    | Tout _ => 0
    | Tcons t ar => S (nb_args ar)
  end.

(* list of argument types *)
Fixpoint arg_interp (ar : arity) :=
  match ar with
    | Tout _ => nil
    | Tcons t ar => cons (base_interp t) (arg_interp ar)
  end.

(* result type *)
Fixpoint res_interp (ar : arity) :=
  match ar with
    | Tout t => base_interp t
    | Tcons _ ar => res_interp ar
  end.

(* base_type of result to const *)
Definition base_to_const t :=
  match t as t' return base_interp t' -> const with
    | Tint => fun v => Cint v
    | Tbool => fun b => Cbool b
  end.

(** Two possible versions: 
    1) arguments must be correct
    2) arguments are checked to have the proper type *)

(* Version 1 *)
(* List of valid arguments *)
Inductive valid_args : arity -> Set :=
  | noArg : forall t_out, valid_args (Tout t_out)
  | moreArg : forall {t_in ar} (c : base_interp t_in) (l : valid_args ar), valid_args (Tcons t_in ar).

(* TODO: make a better definition *)
Fixpoint apply_arity_1 {ar : arity} (f : arrows ar) (args : valid_args ar) : res_interp ar.
destruct ar; simpl in *.
- exact f.
- inversion_clear args.
  exact (apply_arity_1 ar (f c) l).
Defined.

(* Version 2 *)
(* Predicate accepting list of valid arguments *)
Inductive Valid_args : arity -> nelist const -> Prop :=
  | OneInt : forall t_out n, Valid_args (Tcons Tint (Tout t_out)) (nebase (Cint n))
  | OneBool : forall t_out b, Valid_args (Tcons Tbool (Tout t_out)) (nebase (Cbool b))
  | MoreInt : forall ar (n : Z) l, Valid_args ar l -> Valid_args (Tcons Tint ar) (necons (Cint n) l)
  | MoreBool : forall ar (b : bool) l, Valid_args ar l -> Valid_args (Tcons Tbool ar) (necons (Cbool b) l).

Lemma Valid_args_length : forall ar l, Valid_args ar l -> Nelist.length l = nb_args ar.
Proof. intros ar l Hvalid. induction Hvalid; simpl; auto. Qed.

Fixpoint apply_arity (ar : arity) (l : nelist const) : arrows ar -> option const :=
  match ar as ar', l return arrows ar' -> option const with
    | Tout _, _ => fun _ => None
    | Tcons Tint (Tout Tint), nebase (Cint n) => fun f => Some (Cint (f n))
    | Tcons Tint (Tout Tbool), nebase (Cint n) => fun f => Some (Cbool (f n))
    | Tcons Tbool (Tout Tint), nebase (Cbool b) => fun f => Some (Cint (f b))
    | Tcons Tbool (Tout Tbool), nebase (Cbool b) => fun f => Some (Cbool (f b))
    | Tcons Tint ar, necons (Cint n) l => fun f => apply_arity ar l (f n)
    | Tcons Tbool ar, necons (Cbool b) l => fun f => apply_arity ar l (f b)
    | _, _ => fun _ => None (* Wrong type or number of arguments *)
  end.

Definition apply_op (op : operator) (l : nelist const) : option const :=
  apply_arity (get_arity op) l (get_interp op).
