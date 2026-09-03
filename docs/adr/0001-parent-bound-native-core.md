# Use a parent-bound Go core over JSONL

Syncshell 0.1.8 uses one Go child process per rich host and a bounded,
versioned JSONL protocol over standard input and output. A stateless command
cannot own the Event API cursor and recovery state, while a daemon and control
socket would add client brokerage that no supported 0.1.8 host needs.

The core may become a daemon only when a supported target needs simultaneous
independent rich clients, shared state or notifications across host processes,
a core that survives its host, or a host that cannot supervise a child.
