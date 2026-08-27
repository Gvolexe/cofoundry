#!/bin/sh
set -eu

: "${CF_BUILT_VMID:?CF_BUILT_VMID is required}"

echo "==> starting deferred Windows seal task through QEMU guest agent"
qm guest exec "$CF_BUILT_VMID" -- powershell.exe -NoLogo -NoProfile -NonInteractive \
  -Command "Start-ScheduledTask -TaskName 'PackerFinalizeSeal'" >/dev/null

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
