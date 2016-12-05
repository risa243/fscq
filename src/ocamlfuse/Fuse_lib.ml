(*
  This file is part of the "OCamlFuse" library.

  OCamlFuse is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation (version 2 of the License).
  
  OCamlFuse is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
  
  You should have received a copy of the GNU General Public License
  along with OCamlFuse.  See the file LICENSE.  If you haven't received
  a copy of the GNU General Public License, write to:
  
  Free Software Foundation, Inc.,
  59 Temple Place, Suite 330, Boston, MA
  02111-1307  USA

  Vincenzo Ciancia

  applejack@users.sf.net
  vincenzo_ml@yahoo.it
*)

open Fuse_bindings
open String
open Thread
open Result

let _ = Callback.register "ocaml_list_length" List.length

external is_null : 'a Com.opaque -> bool = "ocaml_fuse_is_null"

let undefined _ = raise (Unix.Unix_error (Unix.ENOSYS,"undefined",""))

let worker_thread (q, m, c) =
  Mutex.lock m;
  while true do
    while Queue.length q == 0 do
      Condition.wait c m
    done;
    let (x, y) = Queue.take q in
    Mutex.unlock m;
    ignore (x y);
    Mutex.lock m
  done

let fuse_loop fuse (multithreaded) =
  let q = Queue.create () in
  let m = Mutex.create () in
  let c = Condition.create () in
  for i = 0 to 1 do
    ignore (Thread.create worker_thread (q, m, c));
  done;
  let f =
    if multithreaded (* TODO: thread pooling instead of creation? *)
    then fun x y ->
      Mutex.lock m;
      Queue.add (x, y);
      Mutex.unlock m;
      Condition.signal c
    else fun x y -> ignore (x y)
  in
    while not (__fuse_exited fuse) do
      let cmd = __fuse_read_cmd fuse in
	if not (is_null cmd)
        then f (__fuse_process_cmd fuse) cmd
    done

let _ = Callback.register "ocaml_fuse_loop" fuse_loop

let default_op_names = {
  init = None;
  getattr = None;
  readlink = None;
  readdir = None;
  opendir = None;
  releasedir = None;
  fsyncdir = None;
  mknod = None;
  mkdir = None;
  unlink = None;
  rmdir = None;
  symlink = None;
  rename = None;
  link = None;
  chmod = None;
  chown = None;
  truncate = None;
  utime = None;
  fopen = None;
  read = None;
  write = None;
  statfs = None;
  flush = None;
  release = None;
  fsync = None;
  setxattr = None;
  getxattr = None;
  listxattr = None;
  removexattr = None;
}

let start = ref 0
let supply () = 
  let r = !start in
    start := !start + 1;
    "__caml_cb_" ^ (string_of_int r)

let named_op f =
  if f == undefined
  then None
  else 
    let cb x = 
      try Ok (f x)
      with
	  Unix.Unix_error (err,_,_) -> Bad err
	| _ -> Bad Unix.ERANGE (* TODO: find a better way to signal the user and log this *) 
    in
    let name = supply () in
      Callback.register name cb;
      Some name

let named_op_2 f =
  if f == undefined
  then None
  else 
    let cb x y = 
      try Ok (f x y)
      with	      
	  Unix.Unix_error (err,_,_) -> Bad err
	| _ -> Bad Unix.ERANGE in
    let name = supply () in
      Callback.register name cb;
      Some name

let named_op_3 f =
  if f == undefined
  then None
  else 
    let cb x y z = 
      try Ok (f x y z)
      with	      
	  Unix.Unix_error (err,_,_) -> Bad err
	| _ -> Bad Unix.ERANGE in
    let name = supply () in
      Callback.register name cb;
      Some name

let named_op_4 f =
  if f == undefined
  then None
  else 
    let cb x y z t = 
      try Ok (f x y z t)
      with	      
	  Unix.Unix_error (err,_,_) -> Bad err
	| _ -> Bad Unix.ERANGE in
    let name = supply () in
      Callback.register name cb;
      Some name
