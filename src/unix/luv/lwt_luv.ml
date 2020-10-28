let l f = function
| Result.Error e -> failwith (Luv.Error.err_name e)
| Ok l -> List.iter (function
| `DISCONNECT -> ()
| `PRIORITIZED -> ()
| `READABLE -> f ()
| `WRITABLE -> f ()
) l;

external from_unix_helper : Unix.file_descr -> nativeint -> unit = "luv_unix_fd_to_os_fd"

let from_unix unix_fd =
  let os_fd = Ctypes.make (Luv_c_types.Os_fd.t) in
  let storage = Ctypes.(raw_address_of_ptr (to_voidp (addr os_fd))) in
  from_unix_helper unix_fd storage;
  Ctypes.(!@ (addr os_fd |> to_voidp |> from_voidp Ctypes.int))

let make_loop () =
  Luv.Loop.init () |> function
  | Ok l -> l
  | Result.Error e -> failwith (Printf.sprintf "Could not create new loop, this is probably a error in Lwt, please open a issue on the repo. \nError message: %s" (Luv.Error.err_name e))

  class engine = object
  inherit Lwt_engine.abstract

  val loop = ref (make_loop ())

  method! fork =
    let next_loop = !loop in
    Luv.Loop.fork next_loop |> function
    | Ok () -> loop := next_loop
    | Result.Error e -> failwith (Printf.sprintf "Could not handle fork, this is probably a error in Lwt, please open a issue on the repo. \nError message: %s" (Luv.Error.err_name e))

  method private cleanup = Luv.Loop.stop !loop

  method iter block =
    match (block) with
      | true -> Luv.Loop.run ~loop:!loop ~mode:`ONCE () |> ignore
      | false -> Luv.Loop.run ~loop:!loop ~mode:`NOWAIT () |> ignore

  method private register_readable fd f =
    let p = Luv.Poll.init ~loop:!loop (from_unix fd) in
    match p with
    | Ok poll ->
        let () = Luv.Poll.start poll [`READABLE; `DISCONNECT; `PRIORITIZED;] (l f) in
        lazy(Luv.Poll.stop poll |> ignore)
    | Result.Error e -> failwith (Printf.sprintf "Could not register fd for read polling, this is probably a error in Lwt, please open a issue on the repo. \nError message: %s" (Luv.Error.err_name e))

  method private register_writable fd f =
    let p = Luv.Poll.init ~loop:!loop (from_unix fd) in
    match p with
    | Ok poll ->
      let () = Luv.Poll.start poll [`WRITABLE; `DISCONNECT; `PRIORITIZED;] (l f) in
      lazy(Luv.Poll.stop poll |> ignore)
    | Result.Error e -> failwith (Printf.sprintf "Could not register fd for write polling, this is probably a error in Lwt, please open a issue on the repo. \nError message: %s" (Luv.Error.err_name e))

  method private register_timer delay repeat f =
    let delay_ms = (int_of_float (delay *. 1000.)) in
    let t = Luv.Timer.init ~loop:!loop () in
    match t with
    | Result.Error e -> failwith (Printf.sprintf "Could not initialize a timer, this is probably a error in Lwt, please open a issue on the repo. \nError message: %s" (Luv.Error.err_name e))
    | Ok timer ->
      let timer_fn = match repeat with
      | true -> Luv.Timer.start ~repeat:delay_ms timer
      | false -> Luv.Timer.start timer
      in
      match timer_fn delay_ms f with
      | Ok () -> lazy(Luv.Timer.stop timer |> ignore)
      | Result.Error e -> failwith (Printf.sprintf "Could not start a timer, this is probably a error in Lwt, please open a issue on the repo. \nError message: %s" (Luv.Error.err_name e))
end
