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


let map_token (Specif.Coq_existT (tok, l) : LustreParser.Aut.GramDefs.token) =
  let loc l = (Obj.magic l : LustreAst.astloc) in
  let open LustreParser.Aut.GramDefs in
  match tok with
  | ASSERT't     -> (LustreParser2.ASSERT     (loc l), loc l)
  | AND't        -> (LustreParser2.AND        (loc l), loc l)
  | BOOL't       -> (LustreParser2.BOOL       (loc l), loc l)
  | COLONCOLON't -> (LustreParser2.COLONCOLON (loc l), loc l)
  | COLON't      -> (LustreParser2.COLON      (loc l), loc l)
  | COMMA't      -> (LustreParser2.COMMA      (loc l), loc l)
  | CONSTANT't   -> let v = (Obj.magic l :
                              LustreAst.constant * LustreAst.astloc) in
                   (LustreParser2.CONSTANT  v      , snd v)
  | DOT't        -> (LustreParser2.DOT        (loc l), loc l)
  | ELSE't       -> (LustreParser2.ELSE       (loc l), loc l)
  | EVERY't      -> (LustreParser2.EVERY      (loc l), loc l)
  | EOF't        -> (LustreParser2.EOF        (loc l), loc l)
  | EQ't         -> (LustreParser2.EQ         (loc l), loc l)
  | HASH't       -> (LustreParser2.HASH       (loc l), loc l)
  | FALSE't      -> (LustreParser2.FALSE      (loc l), loc l)
  | FBY't        -> (LustreParser2.FBY        (loc l), loc l)
  | FLOAT32't    -> (LustreParser2.FLOAT32    (loc l), loc l)
  | FLOAT64't    -> (LustreParser2.FLOAT64    (loc l), loc l)
  | FUNCTION't   -> (LustreParser2.FUNCTION   (loc l), loc l)
  | GEQ't        -> (LustreParser2.GEQ        (loc l), loc l)
  | GT't         -> (LustreParser2.GT         (loc l), loc l)
  | IF't         -> (LustreParser2.IF         (loc l), loc l)
  | INT16't      -> (LustreParser2.INT16      (loc l), loc l)
  | INT32't      -> (LustreParser2.INT32      (loc l), loc l)
  | INT64't      -> (LustreParser2.INT64      (loc l), loc l)
  | INT8't       -> (LustreParser2.INT8       (loc l), loc l)
  | LAND't       -> (LustreParser2.LAND       (loc l), loc l)
  | LEQ't        -> (LustreParser2.LEQ        (loc l), loc l)
  | LET't        -> (LustreParser2.LET        (loc l), loc l)
  | LNOT't       -> (LustreParser2.LNOT       (loc l), loc l)
  | LOR't        -> (LustreParser2.LOR        (loc l), loc l)
  | LPAREN't     -> (LustreParser2.LPAREN     (loc l), loc l)
  | LSL't        -> (LustreParser2.LSL        (loc l), loc l)
  | LSR't        -> (LustreParser2.LSR        (loc l), loc l)
  | LT't         -> (LustreParser2.LT         (loc l), loc l)
  | LXOR't       -> (LustreParser2.LXOR       (loc l), loc l)
  | MERGE't      -> (LustreParser2.MERGE      (loc l), loc l)
  | MINUS't      -> (LustreParser2.MINUS      (loc l), loc l)
  | MOD't        -> (LustreParser2.MOD        (loc l), loc l)
  | NEQ't        -> (LustreParser2.NEQ        (loc l), loc l)
  | NODE't       -> (LustreParser2.NODE       (loc l), loc l)
  | NOT't        -> (LustreParser2.NOT        (loc l), loc l)
  | ON't         -> (LustreParser2.ON         (loc l), loc l)
  | ONOT't       -> (LustreParser2.ONOT       (loc l), loc l)
  | OR't         -> (LustreParser2.OR         (loc l), loc l)
  | PLUS't       -> (LustreParser2.PLUS       (loc l), loc l)
  | RARROW't     -> (LustreParser2.RARROW     (loc l), loc l)
  | RESTART't    -> (LustreParser2.RESTART    (loc l), loc l)
  | RETURNS't    -> (LustreParser2.RETURNS    (loc l), loc l)
  | RPAREN't     -> (LustreParser2.RPAREN     (loc l), loc l)
  | SEMICOLON't  -> (LustreParser2.SEMICOLON  (loc l), loc l)
  | SLASH't      -> (LustreParser2.SLASH      (loc l), loc l)
  | STAR't       -> (LustreParser2.STAR       (loc l), loc l)
  | TEL't        -> (LustreParser2.TEL        (loc l), loc l)
  | THEN't       -> (LustreParser2.THEN       (loc l), loc l)
  | TRUE't       -> (LustreParser2.TRUE       (loc l), loc l)
  | UINT16't     -> (LustreParser2.UINT16     (loc l), loc l)
  | UINT32't     -> (LustreParser2.UINT32     (loc l), loc l)
  | UINT64't     -> (LustreParser2.UINT64     (loc l), loc l)
  | UINT8't      -> (LustreParser2.UINT8      (loc l), loc l)
  | VAR't        -> (LustreParser2.VAR        (loc l), loc l)
  | VAR_NAME't   -> let v = (Obj.magic l :
                                LustreAst.ident * LustreAst.astloc) in
                   (LustreParser2.VAR_NAME    v      , snd v)
  | WHEN't       -> (LustreParser2.WHEN       (loc l), loc l)
  | WHENOT't     -> (LustreParser2.WHENOT     (loc l), loc l)
  | XOR't        -> (LustreParser2.XOR        (loc l), loc l)
