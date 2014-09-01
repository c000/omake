
(*
 * Info needed for a debug variable.
 *)
type debug_info =
  { debug_name : string;
    debug_description : string;
    debug_value : bool
  }

(*
 * Info about variables.
 *)
type info =
  { info_name : string;
    mutable info_info : string option;
    info_flag : bool ref
  }

(*
 * Perform debugging?
 * Set this function to false to disable all debugging.
 *)
let debug_enabled =  true

let debug flag =
  debug_enabled && !flag

let debug_level flag i =
  debug_enabled && !flag >= i




(*  Initial info is empty. *)
let info = ref []

(*  Description of debug flags added from the command line. *)
let default_description = "Unitialized debug flag"


(*  List all the debug flags. *)
let debuggers () =
  let collect { info_name = name; info_info = info; info_flag = flag } =
    let info =
      match info with
      |Some info ->
        info
      | None ->
        default_description in
    { debug_name = name; debug_description = info; debug_value = !flag }
  in
  Array.of_list (List.map collect !info)


(*
 * Print a usage argument.
 *)
let debug_usage () =
  let usage { debug_name = name; debug_description = desc; debug_value = flag } =
  Printf.eprintf "\t%s: %s: %b\n" name desc flag  in
  Printf.eprintf "Debugging flags:\n";
  Printf.eprintf "You can specify these as a colon-separated list\n";
  Array.iter usage (debuggers ());
  flush stderr

(*  Create a debugging variable. *)
let create_debug
    { debug_name = name;
      debug_description = desc;
      debug_value = flag
    } =
  let rec search = function
    | ({ info_name = name'; info_info = desc'; info_flag = flag' } as x)
      :: t ->
        if name = name' then

        begin match desc' with
        | None ->
          x.info_info <- Some desc;
          flag'
        | Some desc' ->
          if desc <> desc' then
            raise (Failure (Printf.sprintf "Lm_debug.create_debug: variable '%s' is already created with a different description" name))
          else
            flag'
        end
      else  search t
    | [] ->
      let flag' = ref flag in
      info := { info_name = name;
          info_info = Some desc;
          info_flag = flag'
        } :: !info;
      flag'
  in
  search !info 

(*
 * Get the value of a debugging variable.
 *)
let load_debug name =
  let rec search = function
    | { info_name = name'; info_flag = flag ; _} :: t ->
      if name' = name then
        flag
      else
        search t
    | [] ->
      raise (Failure (Printf.sprintf "Lm_debug.load_debug: variable '%s' has not been created" name))
  in
  search !info

(*
 * Modify a debugging flag.
 *)
let set_debug name flag =
  let rec search = function
      h :: t ->
      let { info_name = name'; info_flag = flag'; _ } = h in
      if name' = name then
        flag' := flag
      else
        search t
    | [] -> raise (Failure "set_debug")
  in
  search !info

(*
 * Possible debug flag.
 * Try setting the flag first.
 *)
let set_possible_debug name flag =
  try set_debug name flag with
    Failure "set_debug" ->
    let flag' = ref flag in
    let ninfo =
      { info_name = name;
        info_info = None;
        info_flag = flag'
      }
    in
    info := ninfo :: !info

(*
 * Get the value of a debugging flag.
 *)
let get_debug name =
  let rec search = function
      h :: t ->
      if h.info_name = name then
        let { info_info = description; info_flag = flag ; _} = h in
        let description =
          match description with
            Some desc ->
            desc
          | None ->
            default_description
        in
        { debug_name = name;
          debug_description = description;
          debug_value = !flag
        }
      else
        search t
    | [] ->
      Printf.eprintf "Lm_debug.get_debug: no such variable: %s\n%t" name flush;
      raise (Failure "get_debug")
  in
  search !info

(*
 * Check for no remaining possible debug flags.
 *)
let check_debug () =
  ()

(************************************************************************
 * PARTICULAR DEBUG                                                     *
 ************************************************************************)

(*
 * File loading.
 *)
let debug_load =
  create_debug (**)
    { debug_name = "load";
      debug_description = "Print file names as they load";
      debug_value = false
    }

let eflush outx =
  output_char outx '\n';
  flush outx

let show_loading s =
  if !debug_load then
    Printf.eprintf s eflush

(*
 * Split a string at a particular char.
 *)
let split c s =
  let len = String.length s in
  let rec loop i j =
    if j = len then
      if i = j then
        []
      else
        [String.sub s i (j - i)]
    else if String.contains c s.[j] then
      if i = j then
        loop (j + 1 ) (j + 1)
      else
        String.sub s i (j - i) :: loop ( j + 1) ( j + 1)
    else
      loop i (succ j)
  in
  loop 0 0

(*
 * Set debug flags from the environment.
 *)
let set_possible_debug_flags _ _ flags =
  List.iter (fun name -> set_possible_debug name true) (split ":" flags)

let set_debug_flags flags =
  let names = split ":" flags in
  try List.iter (fun name -> set_debug name true) names with
    Failure _ ->
    debug_usage ();
    exit 1

(*************************************************************************
 * AD-HOC PROFILING
*)

open Unix

type times = 
  {
    mutable calls : int;
    mutable wtime : float;
    mutable utime : float;
    mutable stime : float
  }

type profile = {
  ok : times;
  exn : times
}

type 'a res =
  | Ok of 'a
  | Exn of exn

let tbl = Hashtbl.create 19

let compare (_,t1) (_,t2) =
  (t1.ok.wtime +. t1.exn.wtime) <= (t2.ok.wtime +. t2.exn.wtime)

let report1 s t =
  let calls_f = float_of_int t.calls in
  Printf.eprintf "\t%s:\n\t\tCalls: %i;\n\t\tTime elapsed: %0.3fs (%0.6fs/call);\n\t\tSystem time: %0.2fs (%0.6fs/call);\n\t\tUser time: %0.2fs (%0.6fs/call).\n" (**)
    s t.calls t.wtime (t.wtime /. calls_f) t.stime (t.stime /. calls_f) t.utime (t.utime /. calls_f)

let report (s, t) =
  Printf.eprintf "Timing information for %s (%0.3fs total):\n" s 
    (t.ok.wtime +. t.exn.wtime);
  if t.ok.calls <> 0 then report1 
      (if t.exn.calls <> 0 then "Successful calls" else "All calls succeeded")
      t.ok;
  if t.exn.calls <> 0 then report1
      (if t.ok.calls <> 0 then "Failed calls" else "All calls failed") t.exn;
  if t.ok.calls <> 0 && t.exn.calls <> 0 then report1 "Total calls" 
      {
        calls = t.ok.calls + t.exn.calls;
        wtime = t.ok.wtime +. t.exn.wtime;
        utime = t.ok.utime +.  t.exn.utime;
        stime = t.ok.stime +.  t.exn.stime
      }

let add s t l = (s,t) :: l

let report_timing () =
  if Hashtbl.length tbl > 0 then
    List.iter report (Sort.list compare (Hashtbl.fold add tbl []))

let () = at_exit report_timing

let timing_wrap s f arg =
  let start_f = gettimeofday () in
  let start_p = times () in
  let res =
    try Ok (f arg)
    with exn -> Exn exn
  in
  let end_f = gettimeofday () in
  let end_p = times () in
  let times =
    try Hashtbl.find tbl s
    with Not_found ->
      let times = {
        ok = {calls = 0; wtime = 0.0; utime = 0.0; stime = 0.0};
        exn = {calls = 0; wtime = 0.0; utime = 0.0; stime = 0.0}}
      in
      Hashtbl.add tbl s times;
      times
  in
  let times =
    match res with
    | Ok _ -> times.ok
    | Exn _ -> times.exn
  in
  times.calls <- times.calls + 1;
  times.wtime <- times.wtime +. end_f -. start_f;
  times.utime <- times.utime +. end_p.tms_utime -. start_p.tms_utime;
  times.stime <- times.stime +. end_p.tms_stime -. start_p.tms_stime;
  match res with
  | Ok res -> res
  | Exn exn -> raise exn
