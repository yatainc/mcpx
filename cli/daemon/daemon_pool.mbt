///|
async fn DaemonPool::entry(
  self : DaemonPool,
  group : @async.TaskGroup[Unit],
  key : String,
  server : @config.McpServerConfig,
) -> DaemonEntry raise McpxDaemonError {
  self.lock.acquire()
  let existing = self.entries.get(key)
  match existing {
    Some(value) if !value.is_idle_expired() => {
      self.lock.release()
      value
    }
    Some(value) => {
      self.entries.remove(key)
      self.lock.release()
      close_entry(value)
      create_and_insert_entry(self, group, key, server)
    }
    None => {
      self.lock.release()
      create_and_insert_entry(self, group, key, server)
    }
  }
}

///|
async fn create_and_insert_entry(
  pool : DaemonPool,
  group : @async.TaskGroup[Unit],
  key : String,
  server : @config.McpServerConfig,
) -> DaemonEntry raise McpxDaemonError {
  let created = create_entry(group, server)
  pool.lock.acquire()
  match pool.entries.get(key) {
    Some(value) => {
      pool.lock.release()
      created.client.close()
      value
    }
    None => {
      pool.entries[key] = created
      pool.lock.release()
      created
    }
  }
}

///|
async fn create_entry(
  group : @async.TaskGroup[Unit],
  server : @config.McpServerConfig,
) -> DaemonEntry raise McpxDaemonError {
  let command = match server.command {
    Some(value) => value
    None => raise RemoteError("server has no command")
  }
  let client = @mcp_stdio.stdio_mcp_connect(
    group,
    command~,
    args=server.args,
    env=server.env,
    cwd=server.cwd,
    mode=@config.effective_connection_mode(server),
  ) catch {
    _ => raise Stdio("mcp stdio error")
  }
  {
    client,
    mutex: Semaphore(1),
    idle_timeout_ms: server_idle_timeout_ms(server),
    last_used_ms: @env.now().reinterpret_as_int64(),
  }
}

///|
fn server_idle_timeout_ms(server : @config.McpServerConfig) -> Int? {
  match server.lifecycle {
    Some({ mode: KeepAlive, idle_timeout_ms, }) => idle_timeout_ms
    _ => None
  }
}

///|
fn DaemonEntry::is_idle_expired(self : DaemonEntry) -> Bool {
  match self.idle_timeout_ms {
    Some(timeout) =>
      @env.now().reinterpret_as_int64() - self.last_used_ms >=
      timeout.to_int64()
    None => false
  }
}

///|
fn DaemonEntry::mark_used(self : DaemonEntry) -> Unit {
  self.last_used_ms = @env.now().reinterpret_as_int64()
}

///|
fn close_entry(entry : DaemonEntry) -> Unit {
  entry.client.close()
}

///|
fn DaemonPool::close_all(self : DaemonPool) -> Unit {
  let entries = []
  for _, entry in self.entries {
    entries.push(entry)
  }
  self.entries.clear()
  for entry in entries {
    close_entry(entry)
  }
}
