# Durable receipts belong outside the public HLS directory. Never delete this
# directory while its database is in use: keys are database row identities.
recovery_dir = environment.get(default="/recovery", "RADIO_RECOVERY_DIR")
media_root = environment.get(default="/media", "RADIO_MEDIA_DIR")
media_prefix =
  if string.contains(suffix="/", media_root) then media_root else "#{media_root}/" end
file.mkdir(parents=true, recovery_dir)

requested = request.queue(id="requested", prefetch=1)
complementary = request.queue(id="complementary", prefetch=1)
resumed = request.queue(id="resumed", prefetch=1, interactive=false)
resume_pending = ref(false)

# ponytail: receipts and admission list grow per delivery (linear admission
# scan); compact DB-acknowledged receipts/use a key set if volume requires it.
# Never expire an unacknowledged completion by age.
def receipt_path(key) = "#{recovery_dir}/#{key}.json" end

def read_receipt_file(filename) =
  let json.parse (receipt : {
    key: string, queue: string, path: string, state: string,
    position: float, sequence: float
  }) = file.contents(filename)
  receipt
end

def read_receipt(key) = read_receipt_file(receipt_path(key)) end

def save_receipt(receipt) =
  file.write(atomic=true, temp_dir=recovery_dir,
    data=json.stringify(compact=true, receipt), receipt_path(receipt.key))
end

def target_queue(kind) =
  if kind == "requested" then requested else complementary end
end

def valid_media_path(media_path) =
  string.contains(prefix=media_prefix, media_path) and
  r/^[a-zA-Z0-9_\/.\-]+$/.test(media_path) and
  not r/(^|\/)\.\.(\/|$)/.test(media_path)
end

# Only the control thread mutates this list. Streaming callbacks update their
# own receipt file atomically, never the admission list.
admitted = ref([])
def admit(receipt, queue) =
  if list.mem(receipt.key, admitted()) then
    true
  else
    uri = 'annotate:recovery_key="#{receipt.key}",recovery_offset="#{receipt.position}",liq_cue_in="#{receipt.position}":#{receipt.path}'
    item = request.create(uri)
    push = queue.push
    if request.resolve(timeout=1., content_type=queue, item) then
      begin
        push(item)
        admitted := list.append(admitted(), [receipt.key])
        true
      end
    else
      # A resolve failure is transient unless the media is definitively absent.
      # Transient receipts stay retryable: Phoenix keeps the row and the next
      # poll calls enqueue again. Missing media gets an explicit failed receipt,
      # which enqueue also re-attempts in case the mount appears later.
      begin
        if file.exists(receipt.path) then
          log("radio_admission_deferred key=#{receipt.key} path=#{receipt.path}")
        else
          log("radio_admission_failed key=#{receipt.key} path=#{receipt.path}")
          save_receipt({...receipt, state="failed"})
        end
        false
      end
    end
  end
end

def enqueue(args) =
  parts = string.split(separator=" ", args)
  if list.length(parts) != 3 then
    "ERROR: invalid delivery"
  else
    key = list.nth(parts, 0)
    kind = list.nth(parts, 1)
    media_path = list.nth(parts, 2)
    if not r/^(requested|complementary)-[1-9][0-9]*$/.test(key) or
       not (kind == "requested" or kind == "complementary") or
       not valid_media_path(media_path)
    then
      "ERROR: invalid delivery"
    else
      if not file.exists(receipt_path(key)) then
        # Intent reaches disk before queue insertion or ACK. A process crash
        # anywhere after this write is recoverable without Phoenix.
        save_receipt({key=key, queue=kind, path=media_path, state="queued",
          position=0., sequence=time()})
      end
      receipt = read_receipt(key)
      if receipt.path != media_path or receipt.queue != kind then
        "ERROR: delivery conflict"
      else
        if receipt.state == "queued" or receipt.state == "failed" then
          begin
            if admit(receipt, target_queue(kind)) then
              begin
                if receipt.state == "failed" then
                  save_receipt({...receipt, state="queued"})
                end
                file.contents(receipt_path(key))
              end
            elsif read_receipt(key).state == "failed" then
              file.contents(receipt_path(key))
            else
              "ERROR: delivery pending"
            end
          end
        elsif receipt.state == "playing" and resume_pending() then
          begin
            ignore(admit(receipt, resumed))
            file.contents(receipt_path(key))
          end
        else
          file.contents(receipt_path(key))
        end
      end
    end
  end
end
server.register(namespace="radio", "enqueue", enqueue)

# Restore in admission order, with the interrupted track ahead of both queues.
# Strict JSON parsing deliberately fails startup on journal corruption rather
# than silently losing deliveries.
receipts = list.map(read_receipt_file, file.ls(absolute=true, pattern="*.json", recovery_dir))
receipts = list.sort(fun (a, b) ->
  if a.sequence < b.sequence then -1 elsif a.sequence > b.sequence then 1 else 0 end,
  receipts)

# At most one delivery can be playing. A crash at a track boundary can leave a
# stale older "playing" receipt: demote it so it re-enters its own queue instead
# of being stranded when the resumed source drains.
resume_key = ref("")
list.iter(fun (receipt) -> begin
  if receipt.state == "playing" then
    if resume_key() == "" then
      resume_key := receipt.key
    elsif receipt.sequence > read_receipt(resume_key()).sequence then
      begin
        save_receipt({...read_receipt(resume_key()), state="queued"})
        resume_key := receipt.key
      end
    else
      save_receipt({...receipt, state="queued"})
    end
  end
end, receipts)

list.iter(fun (receipt) -> begin
  current = read_receipt(receipt.key)
  if current.state == "playing" then
    ignore(admit(current, resumed))
  elsif current.state == "queued" then
    ignore(admit(current, target_queue(current.queue)))
  end
  ()
end, receipts)

resume_pending :=
  if resume_key() == "" then false
  else read_receipt(resume_key()).state != "failed"
  end

current_playback = ref(fun () -> {key="", path="", position=0., offset=0.})
def current_snapshot(_) =
  snapshot = current_playback()
  json.stringify(compact=true, snapshot())
end
server.register(namespace="radio", "current", current_snapshot)

def monitor(~resume=false, queue) =
  active_key = ref("")
  offset = ref(0.)
  last_checkpoint = ref(0.)
  queue.on_track(synchronous=true, fun (track_metadata) -> begin
    active_key := list.assoc(default="", "recovery_key", track_metadata)
    offset := float_of_string(default=0., list.assoc(default="0", "recovery_offset", track_metadata))
    if active_key() != "" then
      receipt = read_receipt(active_key())
      save_receipt({...receipt, state="playing", position=offset()})
      log("radio_track_started key=#{receipt.key} position=#{offset()}")
      last_checkpoint := 0.
      current_playback := fun () ->
        {key=active_key(), path=receipt.path, position=offset() + queue.elapsed(), offset=offset()}
    end
  end)
  queue.on_frame(synchronous=true, fun () -> begin
    if active_key() != "" and queue.elapsed() - last_checkpoint() >= 1. then
      receipt = read_receipt(active_key())
      save_receipt({...receipt, position=offset() + queue.elapsed()})
      last_checkpoint := queue.elapsed()
    end
  end)
  queue.on_position(synchronous=true, remaining=true, position=0., allow_partial=true,
    fun (_, track_metadata) -> begin
      key = list.assoc(default="", "recovery_key", track_metadata)
      if key != "" then
        receipt = read_receipt(key)
        save_receipt({...receipt, state="played", position=offset() + queue.elapsed()})
        log("radio_track_completed key=#{key}")
        if resume then resume_pending := false end
        active_key := ""
      end
    end)
end
monitor(requested)
monitor(complementary)
monitor(resume=true, resumed)

normal_music = fallback(track_sensitive=true, [requested, complementary])
# Decoder readiness is asynchronous. Block normal queues until interrupted audio
# finishes, rather than letting a faster prefetched request displace recovery.
music = switch(track_sensitive=true, [
  ({resume_pending()}, resumed),
  ({not resume_pending()}, normal_music)
])
