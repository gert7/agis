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

0.2

- Introduced return box for return value fidelity

0.2.1

- Added timeout parameter
- Retry the lock if it expires and we don't have a result yet

0.2.8

- Introduced :retry and :once options in agis_defm* methods

0.2.9

- Introduced agis_call with no parameters No-op call

