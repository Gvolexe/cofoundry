# Windows RDP and IPv4 provisioning implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task.

**Goal:** Ship Windows Server 2019, 2022, and 2025 templates that enable secure RDP by default and prove that Cloudbase-Init applies the requested IPv4 address, prefix, gateway, hostname, and Administrator password on a fresh clone.

**Architecture:** Keep RDP enablement inside the shared Windows finalization recipe so every Windows image has the same default. Extend Cofoundry's declarative Windows verification suite to fail when RDP, NLA, the firewall group, or the TCP listener is missing. Treat IPv4 as an end-to-end provisioning contract: compare the Proxmox ConfigDrive input with the fresh guest's adapter state rather than inferring success from an existing, manually edited VM.

**Tech Stack:** Bun/TypeScript, PowerShell, Packer, Cloudbase-Init, Proxmox VE, Cofoundry `cf build` and `cf verify`, Coport.

**Reference:** [ConvoyPanel/cofoundry PR #33](https://github.com/ConvoyPanel/cofoundry/pull/33)

**Global constraints:** Preserve panel theming, SMTP settings, Linux templates, and running customer VMs. Use rollback copies before replacing VMIDs 2000-2002. Never accept a pre-existing Windows guest as proof because its network and RDP settings may have been edited manually.

---

### Task 1: Reproduce both defects on a disposable clone

**Files:**
- Inspect: `recipes/_shared/windows/Install.ps1`
- Inspect: `recipes/_shared/windows/Finalize.ps1`
- Inspect: `src/verify/checks/windows.ts`
- Record: `docs/windows.md`

1. Clone the current Windows Server 2022 production template to an unused high VMID.
2. Attach an isolated test ConfigDrive payload containing a distinctive IPv4 `/27`, hostname, and password.
3. Boot and wait for Cloudbase-Init to complete its reboot.
4. Compare `qm cloudinit dump` against `Get-NetIPConfiguration`, Cloudbase-Init logs, hostname, password timestamp, RDP registry state, firewall rules, and the 3389 listener.
5. Destroy only the disposable VM after evidence is captured.

### Task 2: Add a failing verifier regression

**Files:**
- Modify: `tests/verify-checks.test.ts`
- Modify: `src/verify/checks/windows.ts`

1. Add a test asserting that the Windows first-boot suite includes a fail-severity RDP contract check.
2. Run `bun test tests/verify-checks.test.ts` and confirm the new test fails because the check is absent.
3. Add the minimal verifier check for Terminal Services policy, NLA, enabled firewall rules, and a 3389 listener.
4. Run the focused test and confirm it passes.
5. Temporarily break the protected check, prove the guard fails, restore it, and prove it passes.

### Task 3: Enable RDP in all Windows recipes

**Files:**
- Modify: `recipes/_shared/windows/Finalize.ps1`
- Modify: `tests/windows-ps-syntax.test.ts`
- Modify: `docs/windows.md`

1. Add a static recipe regression that protects the locale-independent firewall group and RDP registry policy.
2. Run the focused test and confirm it fails.
3. In the post-generalize section, enable Terminal Services, keep NLA required, and enable the built-in Remote Desktop firewall group using its resource identifier.
4. Record the experiment, reason, and acceptance boundary in `docs/windows.md`.
5. Run PowerShell parse checks and the focused tests.

### Task 4: Hold panel completion until Windows provisioning is real

**Files:**
- Modify: `../panel/app/Services/Servers/ServerBuildDispatchService.php`
- Create: `../panel/app/Jobs/Server/WaitForWindowsProvisioningJob.php`
- Modify: `../panel/app/Repositories/Proxmox/Server/ProxmoxGuestAgentRepository.php`
- Test: `../panel/tests/Unit/Services/Servers/ServerBuildDispatchServiceTest.php`
- Test: `../panel/tests/Unit/Jobs/Server/WaitForWindowsProvisioningJobTest.php`

1. Add a dispatch regression requiring a Windows readiness job after power-on and before the install status is cleared or credentials are emailed.
2. Run the focused test and confirm it fails because the job is absent.
3. Add guest-agent helpers for a bounded PowerShell command and network-interface inventory.
4. Make the readiness job wait for Cloudbase-Init to stop after its hostname reboot, then require the active hostname, primary address/prefix pairs, gateways, configured DNS, and complete RDP policy/firewall/service/listener state; retry while the guest is rebooting or configuration is incomplete.
5. Match the existing network contract by checking only the first configured IPv4 and first configured IPv6 address, and give the job enough time for the bounded Proxmox guest-agent calls.
6. Prove success, incomplete, wrong-prefix, multi-address, and guest-agent-unavailable paths with focused tests.

### Task 5: Validate the source change

**Files:**
- Verify: `recipes/_shared/windows/Finalize.ps1`
- Verify: `src/verify/checks/windows.ts`
- Verify: `tests/`

1. Run `bun run prettier --write src/ tests/`.
2. Run `bun test`.
3. Run `bun run typecheck`.
4. Review the final diff against upstream main and PR #33 for accidental scope changes.
5. Commit the source and plan on `gvol/windows-rdp-default` only after all checks pass.

### Task 6: Build and verify Windows Server 2019, 2022, and 2025

**Files:**
- Build: `recipes/windows-server-2019/`
- Build: `recipes/windows-server-2022/`
- Build: `recipes/windows-server-2025/`
- Output: `dist/`

1. Confirm the build node is healthy and no other Cofoundry build or verify operation is active.
2. Build one Windows recipe at a time, retaining a failed VM for diagnosis before retrying.
3. Run full `cf verify` for each artifact.
4. Require all RDP checks and the existing Windows checks to pass.
5. Verify artifact and sidecar SHA-256 values before deployment.

### Task 7: Replace production templates with rollback protection

**Files:**
- Deploy: production Proxmox template VMIDs `2000`, `2001`, `2002`
- Preserve: timestamped vzdump backups and SHA256SUMS

1. Recheck that all three target VMIDs are stopped templates and that no customer disk depends on them.
2. Back up all three templates and hash the backups.
3. Install the newly verified artifacts at the same VMIDs.
4. Confirm every target is stopped with `template=1`, its boot disk passes `qemu-img check`, and its artifact hash matches the intended build.
5. Roll back the affected VMID immediately if any replacement or validation step fails.

### Task 8: Run real fresh-clone acceptance and regression checks

**Files:**
- Verify: disposable clones only
- Verify: live panel and shop read-only checks

1. Provision one disposable clone from each Windows version with distinct test IPv4 settings and credentials.
2. Prove hostname, Administrator password processing, IPv4 address, exact prefix, gateway, DNS, guest agent, RDP policy, NLA, firewall rules, and 3389 listener inside each guest.
3. Prove TCP 3389 reachability from outside the guest where routing permits it.
4. Destroy only the disposable clones and confirm all running production VMs remain running.
5. Recheck public panel pages, all 16 shop template options, panel theme/settings hashes, and SMTP configuration hashes against the pre-deployment baseline.
