# Syncshell

Syncshell presents one selected Syncthing instance through a host-native shell
surface while keeping Syncthing state and host presentation separately owned.

## Language

**Native core**:
The host-neutral owner of Syncthing connection, state, events, actions, and an
explicitly trusted lifecycle binding.
_Avoid_: Backend daemon, shared service

**Host adapter**:
The owner of one shell's presentation, settings, and platform operations.
_Avoid_: Frontend skin, distribution adapter

**Rich host**:
A persistent shell integration that owns one native-core session and presents
the complete interactive experience.
_Avoid_: Client process, broker

**Standalone harness**:
The maintained shell-neutral consumer used to verify the native-core contract.
It is not a supported end-user host in 0.1.8.
_Avoid_: Generic Syncshell application

**Selected instance**:
The single Syncthing instance whose authenticated state is represented by a
session.
_Avoid_: First instance, default process

**Session**:
The authoritative, bounded view of one selected instance and its serialized
actions.
_Avoid_: Cache, repository

**Complete snapshot**:
The immutable public state of a session at one monotonic revision.
_Avoid_: Patch, event payload

**Action**:
A correlated request that may inspect or mutate the selected instance and has
exactly one result.
_Avoid_: Command event, RPC method

**Operational configuration**:
Host-neutral runtime intent supplied to a session, such as probe timing and
persistent lifecycle intent.
_Avoid_: Syncshell settings, style configuration

**Omarchy settings**:
The four host-owned preferences stored in the existing Omarchy settings file.
_Avoid_: Core configuration, portable settings

**Lifecycle binding**:
An exact service unit plus explicit host authority to associate it with the
selected instance.
_Avoid_: Detected service, active unit

**Managed instance**:
A selected instance whose lifecycle binding is authorized and verified for its
target.
_Avoid_: Running service

**External instance**:
A selected instance without a verified lifecycle binding. It remains usable
through its healthy API but exposes no unrelated lifecycle controls.
_Avoid_: Unmanaged error, stopped service

**Stopped candidate**:
An authorized default lifecycle binding that is offline and may be started,
but is not managed until the expected target authenticates.
_Avoid_: Offline instance

**Freshness**:
Whether a complete snapshot reflects a recent authoritative hydration.
_Avoid_: Online state
