0.1.6

- Allows passing Symbols instead of Procs for calling other object methods, usage: agis_defm0($redis, :methodname) - no proc
- Redis parameter no longer passed in to method calls

0.1.7

- Removed agis_push
- Fixed size queue frames
- Idempotent retrying approach

0.1.9

- Retry if exceptions or crash, only remove from queue if return

0.1.10

- Fixed a deadly mailbox failure

