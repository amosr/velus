Require Import Coq.FSets.FMapPositive.
Require Coq.MSets.MSets.
Require Import PArith.

(** * Common definitions *)

Module PS := Coq.MSets.MSetPositive.PositiveSet.
Module PM := Coq.FSets.FMapPositive.PositiveMap.

Definition ident := positive.
Definition ident_eq_dec := Pos.eq_dec.

Lemma In_dec:
  forall x S, {PS.In x S}+{~PS.In x S}.
Proof.
  intros i m; unfold PS.In; case (PS.mem i m); auto.
Qed.

Inductive const : Set :=
| Cint : BinInt.Z -> const
| Cbool : bool -> const.

Lemma Forall_cons2:
  forall A P (x: A) l,
    List.Forall P (x :: l) <-> P x /\ List.Forall P l.
Proof. intros; split; inversion_clear 1; auto. Qed.

