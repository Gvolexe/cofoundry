#!/bin/sh
set -eu

: "${CF_BUILT_VMID:?CF_BUILT_VMID is required}"

echo "==> starting deferred Windows seal task through QEMU guest agent"
agent_deadline=$(( $(date +%s) + 300 ))
last_agent_error="guest agent did not answer"
seal_started=0
while [ "$(date +%s)" -lt "$agent_deadline" ]; do
  status=$(qm status "$CF_BUILT_VMID" 2>/dev/null | awk '{print $2}')
  if [ "$status" = "stopped" ]; then
    # A lost reply can race the seal task's shutdown. The offline sentinel gate
    # that follows is authoritative, so let it distinguish a completed seal
    # from an unrelated stop instead of failing this transport handoff early.
    echo "==> VM $CF_BUILT_VMID stopped during guest-agent handoff; deferring to offline seal gate"
    exit 0
  fi

  # Proxmox 9 has no `qm guest ping` command. Retry the supported guest-exec
  # operation directly, and bound each transport attempt so the outer five-
  # minute deadline remains real even if an agent socket wedges.
  if agent_output=$(timeout 15 qm guest exec "$CF_BUILT_VMID" -- powershell.exe -NoLogo -NoProfile -NonInteractive \
    -Command "\$task = Get-ScheduledTask -TaskName 'PackerFinalizeSeal'; if (\$task.State -eq 'Ready') { Start-ScheduledTask -TaskName 'PackerFinalizeSeal' }" 2>&1); then
    seal_started=1
    break
  fi
  last_agent_error=$agent_output
  sleep 5
done

if [ "$seal_started" -ne 1 ]; then
  echo "QEMU guest agent did not accept the deferred seal task within 5m: $last_agent_error" >&2
  exit 1
fi
echo "==> deferred Windows seal task accepted by guest agent"

# The task waits 10s before sysprep so the guest-agent request can return, then
# generalizes, validates RDP, removes build-only WinRM exposure, writes the
# sentinel, and powers off. Wait for the actual power state rather than sleeping
# blindly; the post-processor performs the authoritative offline sentinel gate.
deadline=$(( $(date +%s) + 900 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  status=$(qm status "$CF_BUILT_VMID" 2>/dev/null | awk '{print $2}')
  if [ "$status" = "stopped" ]; then
    echo "==> deferred Windows seal task powered off VM $CF_BUILT_VMID"
    exit 0
  fi
  sleep 5
done

echo "deferred Windows seal task did not power off VM $CF_BUILT_VMID within 15m" >&2
exit 1
