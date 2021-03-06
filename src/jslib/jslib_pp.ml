(*
 * This file is part of ocamljs, OCaml to Javascript compiler
 * Copyright (C) 2007-9 Skydeck, Inc
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the Free
 * Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
 * MA 02111-1307, USA
 *)

open Format
open Jslib_ast

(* XXX figure out how Format works *)

(*
  precedence, see ECMA 262:
  http://www.ecma-international.org/publications/files/EMCA-ST/Ecma-262.pdf
*)
let p = 0
let pAssignment = 2
let pConditional = 4
let pLogicalOR = 6
let pLogicalAND = 8
let pBitwiseOR = 10
let pBitwiseXOR = 12
let pBitwiseAND = 14
let pEquality = 16
let pRelational = 18
let pShift = 20
let pAdditive = 22
let pMultiplicative = 24
let pUnary = 26
let pPostfix = 28
let pLeftHandSide = 30
let pCall = 32
let pMember = 34
let pPrimary = 36


module JSString =
struct

  (* UChar and UTF8 taken from camomile 0.7.2 *)
  module UChar : sig
    type t
    external uint_code : t -> int = "%identity"
    type uchar = t
    val of_int : int -> uchar
  end =
  struct
    (* $Id: uChar.ml,v 1.4 2004/09/04 16:07:38 yori Exp $ *)
    (* Copyright 2002, 2003 Yamagata Yoriyuki. distributed with LGPL *)
    
    type t = int

    external uint_code : t -> int = "%identity"

    let chr_of_uint n = 
      if n lsr 31 = 0 then n else 
      invalid_arg "UChar.char_of_uint"
      
    type uchar = t

    let of_int n = chr_of_uint n
  end

  module UTF8 : sig
    type t = string
    val iter : (UChar.t -> unit) -> t -> unit
  end =
  struct
    (* $Id: uTF8.ml,v 1.11 2004/09/04 16:07:38 yori Exp $ *)
    (* Copyright 2002, 2003 Yamagata Yoriyuki. distributed with LGPL *)

    type t = string

    let look s i =
      let n' =
        let n = Char.code s.[i] in
        if n < 0x80 then n else
        if n <= 0xdf then
          (n - 0xc0) lsl 6 lor (0x7f land (Char.code s.[i + 1]))
        else if n <= 0xef then
          let n' = n - 0xe0 in
          let m0 = Char.code s.[i + 2] in
          let m = Char.code (String.unsafe_get s (i + 1)) in
          let n' = n' lsl 6 lor (0x7f land m) in
          n' lsl 6 lor (0x7f land m0)
        else if n <= 0xf7 then
          let n' = n - 0xf0 in
          let m0 = Char.code s.[i + 3] in
          let m = Char.code (String.unsafe_get s (i + 1)) in
          let n' = n' lsl 6 lor (0x7f land m) in
          let m = Char.code (String.unsafe_get s (i + 2)) in
          let n' = n' lsl 6 lor (0x7f land m) in
          n' lsl 6 lor (0x7f land m0)     
        else if n <= 0xfb then
          let n' = n - 0xf8 in
          let m0 = Char.code s.[i + 4] in
          let m = Char.code (String.unsafe_get s (i + 1)) in
          let n' = n' lsl 6 lor (0x7f land m) in
          let m = Char.code (String.unsafe_get s (i + 2)) in
          let n' = n' lsl 6 lor (0x7f land m) in
          let m = Char.code (String.unsafe_get s (i + 3)) in
          let n' = n' lsl 6 lor (0x7f land m) in
          n' lsl 6 lor (0x7f land m0)     
        else if n <= 0xfd then
          let n' = n - 0xfc in
          let m0 = Char.code s.[i + 5] in
          let m = Char.code (String.unsafe_get s (i + 1)) in
          let n' = n' lsl 6 lor (0x7f land m) in
          let m = Char.code (String.unsafe_get s (i + 2)) in
          let n' = n' lsl 6 lor (0x7f land m) in
          let m = Char.code (String.unsafe_get s (i + 3)) in
          let n' = n' lsl 6 lor (0x7f land m) in
          let m = Char.code (String.unsafe_get s (i + 4)) in
          let n' = n' lsl 6 lor (0x7f land m) in
          n' lsl 6 lor (0x7f land m0)
        else invalid_arg "UTF8.look"
      in
      UChar.of_int n'
    
    let rec search_head s i =
      if i >= String.length s then i else
      let n = Char.code (String.unsafe_get s i) in
      if n < 0x80 || n >= 0xc2 then i else
      search_head s (i + 1)

    let next s i = 
      let n = Char.code s.[i] in
      if n < 0x80 then i + 1 else
      if n < 0xc0 then search_head s (i + 1) else
      if n <= 0xdf then i + 2
      else if n <= 0xef then i + 3
      else if n <= 0xf7 then i + 4
      else if n <= 0xfb then i + 5
      else if n <= 0xfd then i + 6
      else invalid_arg "UTF8.next"
    
    let rec iter_aux proc s i =
      if i >= String.length s then () else
      let u = look s i in
      proc u;
      iter_aux proc s (next s i)
    
    let iter proc s = iter_aux proc s 0
  end

  let sprint_uchar u =
    let n = UChar.uint_code u in
    let n2 = n land 0xffff in
    let n1 = n lsr 16 in
    if n1 = 0
    then Printf.sprintf "\\u%04X" n2
    else Printf.sprintf "\\U%04X%04X" n1 n2

  let escaped s =
    let buf = Buffer.create 0 in
    let proc u =
      let n = UChar.uint_code u in
      if n > 0x7f || n < 0
      then Buffer.add_string buf (sprint_uchar u)
      else if n = 39
      then Buffer.add_string buf "\\'"
      else Buffer.add_string buf (String.escaped (String.make 1 (Char.chr n))) in

    UTF8.iter proc s;
    Buffer.contents buf

end

let id ppf i = fprintf ppf "%s" i

let ids ppf is =
  let com = ref false in
  List.iter
    (fun i ->
      if !com then fprintf ppf ",@ " else com := true;
      fprintf ppf "%a" id i)
    is

let is_postop = function
  | Jadd2_post | Jsub2_post -> true
  | _ -> false

let unop_op = function
  | Jdelete -> "delete"
  | Jvoid -> "void"
  | Jtypeof -> "typeof"
  | Jadd2_pre -> "++"
  | Jsub2_pre -> "--"
  | Jadd_pre -> "+"
  | Jsub_pre -> "-"
  | Jtilde -> "~"
  | Jnot -> "!"
  | Jadd2_post -> "++"
  | Jsub2_post -> "--"

let binop_op = function
  | Jmul -> "*"
  | Jdiv -> "/"
  | Jmod -> "%"
  | Jadd -> "+"
  | Jsub -> "-"
  | Jlsr -> ">>"
  | Jlsl -> "<<"
  | Jasr -> ">>>"
  | Jlt -> "<"
  | Jgt -> ">"
  | Jleq -> "<="
  | Jgeq -> ">="
  | Jinstanceof -> assert false
  | Jeq -> "=="
  | Jneq -> "!="
  | Jseq -> "==="
  | Jsneq -> "!=="
  | Jand -> "&"
  | Jxor -> "^"
  | Jor -> "|"
  | Jland -> "&&"
  | Jlor -> "||"
  | Jcomma -> ","
  | Jhashref -> assert false
  | Jassign -> "="
  | Jmul_assign -> "*="
  | Jdiv_assign -> "/="
  | Jmod_assign -> "%="
  | Jadd_assign -> "+="
  | Jsub_assign -> "-="
  | Jlsl_assign -> "<<="
  | Jlsr_assign -> ">>="
  | Jasr_assign -> ">>>="
  | Jand_assign -> "&="
  | Jxor_assign -> "^="
  | Jor_assign -> "|="

let binop_prec = function
  | Jeq -> pEquality
  | Jneq -> pEquality
  | Jseq -> pEquality
  | Jsneq -> pEquality
  | Jhashref -> pCall
  | Jlt -> pRelational
  | Jgt -> pRelational
  | Jleq -> pRelational
  | Jgeq -> pRelational
  | Jinstanceof -> pRelational
  | Jlsr -> pShift
  | Jlsl -> pShift
  | Jasr -> pShift
  | Jmul -> pMultiplicative
  | Jdiv -> pMultiplicative
  | Jmod -> pMultiplicative
  | Jadd -> pAdditive
  | Jsub -> pAdditive
  | Jand -> pBitwiseAND
  | Jxor -> pBitwiseXOR
  | Jor -> pBitwiseOR
  | Jland -> pLogicalAND
  | Jlor -> pLogicalOR
  | Jcomma -> p
  | Jassign -> pAssignment
  | Jmul_assign -> pAssignment
  | Jdiv_assign -> pAssignment
  | Jmod_assign -> pAssignment
  | Jadd_assign -> pAssignment
  | Jsub_assign -> pAssignment
  | Jlsl_assign -> pAssignment
  | Jlsr_assign -> pAssignment
  | Jasr_assign -> pAssignment
  | Jand_assign -> pAssignment
  | Jxor_assign -> pAssignment
  | Jor_assign -> pAssignment

let prec = function
  | Jthis _ -> pPrimary
  | Jvar _ -> pPrimary
  | Jarray _ -> pPrimary
  | Jobject _ -> pPrimary
  | Jstring _ -> pPrimary
  | Jnum _ -> pPrimary
  | Jnull _ -> pPrimary
  | Jfun _ -> pPrimary
  | Jbool _ -> pPrimary
  | Jregexp _ -> pPrimary

  | Jfieldref _ -> pMember
  | Jnew _ -> pMember

  | Junop (_, op, _) -> if is_postop op then pPostfix else pUnary
  | Jbinop (_, op, _, _) -> binop_prec op

  | Jite _ -> pConditional
  | Jcall _ -> pCall
  | Jexp_Ant _ -> pPrimary

  | Jexp_nil _ -> assert false
  | Jexp_cons _ -> assert false

let opt f ppf x =
  match x with
    | None -> ()
    | Some x -> f ppf x

let opt_nbsp f ppf x =
  match x with
    | None -> ()
    | Some x ->
        fprintf ppf " ";
        f ppf x

let rec stmt_iter f = function
  | Jstmt_nil _ -> ()
  | Jstmt_cons (_, s1, s2) ->
      stmt_iter f s1;
      stmt_iter f s2
  | s -> f s

let rec expp pr ppf e =
  if prec e < pr
  then fprintf ppf "(@[%a@])" exp e
  else exp ppf e

and exp ppf = function
  | Jthis _  -> fprintf ppf "this"
  | Jvar (_, i) -> fprintf ppf "%s" i
  | Jarray (_, es) -> fprintf ppf "@[<hv>[@;<1 2>%a@ ]@]" aexps es
  | Jobject (_, kvs) ->
      let keyvals ppf kvs =
        let com = ref false in
        List.iter
          (fun (k, v) ->
            if !com then fprintf ppf ",@;<1 2>" else com := true;
            fprintf ppf "@[<hv 2>%a:@ %a@]" (expp pAssignment) k (expp pAssignment) v)
          kvs in
      fprintf ppf "@[<hv>{@;<1 2>%a@ }@]" keyvals kvs
  | Jstring (_, s, false) -> fprintf ppf "\"%s\"" (JSString.escaped s)
  | Jstring (_, s, true) -> fprintf ppf "\'%s\'" (JSString.escaped s)
  | Jnum (_, n) -> fprintf ppf "%s" n
  | Jnull _ -> fprintf ppf "null"
  | Jbool (_, b) -> fprintf ppf "%B" b
  | Jregexp (_, r, f) -> fprintf ppf "/%s/%s" r f
  | Jfun (_, io, is, ss) ->
      fprintf ppf "@[<hv>function %a@[<hv 1>(%a)@]%a@]" (opt_nbsp id) io ids is block ss

  | Jfieldref (_, e, i) -> fprintf ppf "@[<hv 2>%a.@,%s@]" (expp pMember) e i

  | Junop (_, op, e) ->
      if is_postop op
      then
        begin
          fprintf ppf "@[%a%s@]" (expp pPostfix) e (unop_op op)
        end
      else
        begin
          match op with
            | Jdelete | Jvoid | Jtypeof -> fprintf ppf "@[%s %a@]" (unop_op op) (expp pUnary) e
            | _ -> fprintf ppf "@[%s%a@]" (unop_op op) (expp pUnary) e
        end

  | Jbinop (_, op, e1, e2) ->
      begin
        match op with
          | Jhashref -> fprintf ppf "@[%a[%a]@]" (expp pCall) e1 (expp p) e2
          | Jcomma -> fprintf ppf "@[%a, %a@]" (expp p) e1 (expp pAssignment) e2
          | _ ->
              let prec = binop_prec op in
              fprintf ppf "@[<hv 2>%a %s@ %a@]" (expp prec) e1 (binop_op op) (expp (prec + 2)) e2
      end

  | Jite (_, i, t, e) ->
      fprintf ppf "@[<hv 2>%a ?@ %a :@ %a@]"
        (expp pLogicalOR) i
        (expp pAssignment) t
        (expp pAssignment) e

  | Jcall (_, e, es) -> fprintf ppf "@[%a@[<hov 1>(%a)@]@]" (expp pCall) e exps es

  | Jnew (_, e, None) -> fprintf ppf "@[new %a@]" (expp pMember) e
  | Jnew (_, e, Some es) -> fprintf ppf "@[new %a@[<hov 1>(%a)@]@]" (expp pMember) e exps es
  | Jexp_Ant (_, s) -> fprintf ppf "$%s$" s

  | Jexp_nil _ -> assert false
  | Jexp_cons _ -> assert false

and exps ppf e =
  match e with
    | Jexp_nil _ -> ()
    | Jexp_cons (_, e1, e2) ->
        exps ppf e1;
        fprintf ppf ",@ ";
        exps ppf e2;
    | _ ->
        (expp pAssignment) ppf e

and aexps ppf e =
  match e with
    | Jexp_nil _ -> ()
    | Jexp_cons (_, e1, e2) ->
        aexps ppf e1;
        fprintf ppf ",@;<1 2>";
        aexps ppf e2;
    | _ ->
        (expp pAssignment) ppf e

and stmt ppf = function
  | Jvars (_, vars) ->
      begin
        match vars with
          | [ (i, None) ] -> fprintf ppf "@[<hv 2>var %s;@]" i
          | [ (i, Some e) ] -> fprintf ppf "@[<hv 2>var %s =@ %a;@]" i (expp pAssignment) e
          | _ ->
              let fvars ppf vars =
                let comma = ref false in
                List.iter
                  (fun (i, e) ->
                    if !comma then fprintf ppf ",@ " else comma := true;
                    match e with
                      | Some e -> fprintf ppf "%s =@;<1 2>%a" i (expp pAssignment) e
                      | None -> fprintf ppf "%s" i)
                  vars in
              fprintf ppf "@[<hv 2>var@ %a;@]" fvars vars
      end

  | Jfuns (_, i, is, ss) ->
      fprintf ppf "@[<hv>function %s @[<hv 1>(%a)@]%a@]" i ids is block ss

  | Jreturn (_, e) -> fprintf ppf "@[<h>return%a;@]" (opt_nbsp (expp p)) e
  | Jcontinue (_, i) -> fprintf ppf "@[<h>continue%a;@]" (opt_nbsp id) i
  | Jbreak (_, i) -> fprintf ppf "@[<h>break%a;@]" (opt_nbsp id) i

  | Jites (_, i, t, None) ->
      fprintf ppf
        "@[<hv>if (%a)%a@]"
        (expp p) i maybe_block t

  | Jites (_, i, t, Some e) ->
      fprintf ppf
        "@[<hv>if (%a)%a@ else%a@]"
        (expp p) i maybe_block t maybe_block e

  | Jswitch (_, e, cs, fss) ->
      let cases ppf (cs, fss) =
        let spc = ref false in
        List.iter
          (fun (i, ss) ->
            if !spc then fprintf ppf "@ " else spc := true;
            fprintf ppf "@[<hv>case %a:%a@]"
              (expp p) i ind_stmts ss)
          cs;
        match fss with
          | Jstmt_nil _ -> ()
          | _ ->
              if !spc then fprintf ppf "@ " else spc := true;
              fprintf ppf "@[<hv>default:%a@]" ind_stmts fss in
      fprintf ppf
        "@[<hv>switch (%a)@ {@ %a@ }@]"
        (expp p) e cases (cs, fss)

  | Jthrow (_, e) -> fprintf ppf "@[throw %a;@]" (expp p) e

  | Jexps (_, (Jcall (_, Jfun _, _) as e)) -> fprintf ppf "@[(%a);@]" (expp p) e
  | Jexps (_, e) -> fprintf ppf "@[%a;@]" (expp p) e

  | Jtrycatch (_, ss, Some (ci, css), Jstmt_nil _) ->
      fprintf ppf "@[<hv>try%a@ catch (%s)%a@]" block ss ci block css
  | Jtrycatch (_, ss, None, fss) ->
      fprintf ppf "@[<hv>try%a@ finally%a@]" block ss block fss
  | Jtrycatch (_, ss, Some (ci, css), fss) ->
      fprintf ppf "@[<hv>try%a@ catch (%s)%a finally%a@]" block ss ci block css block fss

  | Jfor (_, e1, e2, e3, s) ->
      fprintf ppf "@[<hv>for @[<hv 1>(%a;@ %a;@ %a)@]%a@]" (opt (expp p)) e1 (opt (expp p)) e2 (opt (expp p)) e3 maybe_block s

  | Jdowhile (_, s, e) ->
      fprintf ppf "@[<hv>do%a@ while (%a);@]" maybe_block s (expp p) e

  | Jwhile (_, e, s) ->
      fprintf ppf "@[<hv>while (%a)%a@]" (expp p) e maybe_block s

  | Jblock (_, ss) -> fprintf ppf "@[<hv>{%a@ }@]" ind_stmts ss
  | Jwith (_, e, s) -> fprintf ppf "@[<hv>with (%a)%a@]" (expp p) e maybe_block s
  | Jlabel (_, i, s) -> fprintf ppf "@[<hv>%s:%a@]" i maybe_block s
  | Jstmt_Ant (_, s) -> fprintf ppf "$%s$" s

  | (Jstmt_nil _ | Jstmt_cons _) as ss ->
      stmts ppf ss

and block ppf ss = fprintf ppf " {%a@ }" ind_stmts ss

and maybe_block ppf = function
  | Jblock (_, ss) -> block ppf ss
  | Jstmt_nil _ -> fprintf ppf ";"
  | Jstmt_cons (_loc, _, _) as s -> block ppf (Jblock (_loc, s))
  | s -> fprintf ppf "@;<1 2>%a" stmt s

and ind_stmts ppf ss =
  stmt_iter (fun s -> fprintf ppf "@;<1 2>%a" stmt s) ss

and stmts ppf ss =
  let spc = ref false in
  stmt_iter
    (fun s ->
      if !spc then fprintf ppf "@ " else spc := true;
      stmt ppf s)
    ss

let escaped = JSString.escaped
