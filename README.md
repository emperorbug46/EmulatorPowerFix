# EmulatorPowerFix

Fix for a slow Android Emulator on Windows 11 with Intel hybrid CPUs (12th gen and newer, P-cores + E-cores): Windows power-throttles the headless emulator onto the E-cores. Cold boot gets 2–3× slower, and the guest produces an ANR storm. One Win32 call fixes it, with no admin rights.

Upstream report: **[Google Issue Tracker 572278410](https://issuetracker.google.com/issues/572278410)**. Root-cause analysis and measurements by **Mert Özallı** ([@emperorbug46](https://github.com/emperorbug46)).

*Unofficial. Not affiliated with Google, Android or Intel.*

[English](#english) · [Türkçe](#türkçe)

---

## English

### 1. Symptoms

You run the emulator headless (`-no-window`, as CI and UI-test setups do) on a Windows 11 laptop or desktop with an Intel 12th-gen-or-newer CPU, and:

- cold boot takes 75–125 s to `sys.boot_completed`;
- "System UI isn't responding" and other ANRs show up after every boot, and UI tests lose input;
- the device stays unusable for 3–5 minutes;
- Task Manager shows the E-cores at 80–100% and the P-cores almost idle, while `qemu-system-x86_64-headless.exe` stays at about 3–4 logical processors.

Changing RAM, vCPU count, GPU mode, disk or Defender settings does not help.

### 2. Root cause

Windows' Power Throttling (EcoQoS) heuristic sees a process with no visible window and treats it as background work. About 15 s after start, the emulator's qemu process is moved onto the E-cores and kept there. The guest is CPU-starved: it spends 55–70% of its time in kernel mode and its watchdogs fire (ANRs).

Disabling power throttling for the qemu process only (no change to affinity or priority) removes the slowdown completely.

### 3. Measurements

Same AVD (Android 36, google_apis x86_64, 4 vCPUs, 4 GB), cold boot, back-to-back runs on an Intel Core i5-13420H (4 P-cores + 4 E-cores), Windows 11, WHPX, AC power, High performance plan:

| Run | Change | `boot_completed` | ANRs | qemu CPU peak | Guest ≥90% idle |
|---|---|---|---|---|---|
| A | none | 74 s | 10 | ~3.8 LP | not within 200 s |
| B | none | 106 s | 6 | ~3.7 LP | not within 230 s |
| E | none | 126 s | 3 | ~3.8 LP | not within 220 s |
| **C** | **power throttling off for qemu** | **42 s** | **1** | **~9.6 LP** | **after ~92 s** |
| D | off + P-core affinity + HIGH priority | 44 s | 1 | n/a (pinned) | after ~106 s |

Per-core load in run E (qemu started at about t = 47 s):

```
  t    P-core avg  E-core avg
  50     21.6%       20.4%
  65     11.3%       39.8%   <- work starts moving to the E-cores
  75      6.4%       93.8%
 120-220  5-12%      99.7-100%
```

Run D shows that pinning and priority add nothing: the power-throttling opt-out alone is the fix. Full details are in the [upstream report](https://issuetracker.google.com/issues/572278410).

### 4. Usage

Download [`emulator_power_fix.ps1`](emulator_power_fix.ps1), then run it in Windows PowerShell 5.1 or PowerShell 7. No administrator rights needed.

After the emulator has started:

```powershell
powershell -ExecutionPolicy Bypass -File emulator_power_fix.ps1
```

Or start it first and let it wait for the emulator (up to 60 s). This is better, because the throttling starts about 15 s after launch:

```powershell
powershell -ExecutionPolicy Bypass -File emulator_power_fix.ps1 -Wait 60
```

Output:

```
qemu-system-x86_64-headless (PID 1904): power throttling disabled
```

The setting lasts until that emulator process exits, so run it once per emulator start. It also works on an emulator that is already running and throttled: in testing, the P-cores went from 8–15% to 71–91% within 5 s.

Read the script before running it. It is about 60 lines, makes one Win32 call (`SetProcessInformation` with `ProcessPowerThrottling`) for each `qemu-system-*` process, and changes nothing else.

### 5. Permanent alternative (admin)

Windows can remember the exemption per executable (not tested by me; this is the approach reported for VMware Workstation):

```bat
powercfg /powerthrottling disable /path "%LOCALAPPDATA%\Android\Sdk\emulator\qemu\windows-x86_64\qemu-system-x86_64-headless.exe"
```

For the windowed emulator, use `qemu-system-x86_64.exe` in the same folder.

### 6. The real fix

The emulator can opt itself out at startup, which would fix this for every affected Windows user:

```c
PROCESS_POWER_THROTTLING_STATE s = {0};
s.Version     = PROCESS_POWER_THROTTLING_CURRENT_VERSION;
s.ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED |
                PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION;
s.StateMask   = 0;   /* never throttle */
SetProcessInformation(GetCurrentProcess(), ProcessPowerThrottling, &s, sizeof(s));
```

This is proposed in [issue 572278410](https://issuetracker.google.com/issues/572278410). The Windows side (a VM process running WHPX vCPUs should not be classified as background work) has also been reported to Microsoft through Feedback Hub. If this affects you, a **+1** on the issue helps it get prioritized.

### 7. Related

- [VMware Workstation on Windows 11 with Intel hybrid CPUs](https://williamlam.com/2023/11/heads-up-performance-impact-with-VMware-workstation-on-windows-11-with-intel-hybrid-cpus.html): the same mechanism hitting another hypervisor.
- [Microsoft: Process power throttling](https://learn.microsoft.com/windows/win32/api/processthreadsapi/nf-processthreadsapi-setprocessinformation)

### 8. License

MIT. See [LICENSE](LICENSE).

---

## Türkçe

### 1. Belirtiler

Emülatörü penceresiz (`-no-window`; CI ve arayüz testlerinde olduğu gibi) Intel 12. nesil ya da daha yeni işlemcili bir Windows 11 makinede çalıştırıyorsunuz ve:

- soğuk açılış `sys.boot_completed`'a kadar 75–125 sn sürüyor;
- her açılışta "Sistem kullanıcı arayüzü yanıt vermiyor" ve başka ANR'ler çıkıyor, arayüz testleri girdi kaybediyor;
- cihaz 3–5 dakika kullanılamıyor;
- Görev Yöneticisi'nde E-çekirdekler %80–100, P-çekirdekler neredeyse boşta; `qemu-system-x86_64-headless.exe` 3–4 mantıksal işlemcide kalıyor.

RAM, vCPU sayısı, GPU modu, disk ya da Defender ayarlarını değiştirmek işe yaramıyor.

### 2. Kök neden

Windows'un güç kısıtlama (EcoQoS) sezgisi, görünür penceresi olmayan süreci arka plan işi sayıyor. Açılıştan yaklaşık 15 sn sonra emülatörün qemu süreci E-çekirdeklere taşınıyor ve orada tutuluyor. Misafir sistem işlemci açlığı çekiyor: zamanının %55–70'i çekirdek kipinde geçiyor ve bekçi zamanlayıcıları ANR üretiyor.

Yalnız qemu süreci için güç kısıtlamasını kapatmak (benzeşim ya da öncelik değiştirmeden) yavaşlığı tamamen ortadan kaldırıyor.

### 3. Ölçümler

Aynı AVD, soğuk açılış, art arda çalıştırmalar: kısıtlama açıkken 74 / 106 / 126 sn ve 3–10 ANR; **qemu için kısıtlama kapalıyken 42 sn ve 1 ANR**, qemu tepe kullanımı ~3,8 yerine ~9,6 mantıksal işlemci. Tablo ve çekirdek başına yük için İngilizce bölümdeki [Ölçümler](#3-measurements) kısmına bakın.

### 4. Kullanım

[`emulator_power_fix.ps1`](emulator_power_fix.ps1) dosyasını indirip Windows PowerShell 5.1 ya da PowerShell 7'de çalıştırın. Yönetici hakkı gerekmez.

Emülatör açıldıktan sonra:

```powershell
powershell -ExecutionPolicy Bypass -File emulator_power_fix.ps1
```

Ya da önce betiği başlatıp emülatörü beklemesini sağlayın (en çok 60 sn). Kısıtlama açılıştan ~15 sn sonra başladığı için bu daha iyidir:

```powershell
powershell -ExecutionPolicy Bypass -File emulator_power_fix.ps1 -Wait 60
```

Ayar o emülatör süreci kapanana dek geçerlidir; her emülatör açılışında bir kez çalıştırın. Zaten açık ve kısıtlanmış bir emülatörde de çalışır: denemede P-çekirdekler 5 sn içinde %8–15'ten %71–91'e çıktı.

Çalıştırmadan önce betiği okuyun. Yaklaşık 60 satırdır, her `qemu-system-*` süreci için tek bir Win32 çağrısı (`SetProcessInformation`, `ProcessPowerThrottling`) yapar, başka hiçbir şeyi değiştirmez.

### 5. Kalıcı seçenek (yönetici)

```bat
powercfg /powerthrottling disable /path "%LOCALAPPDATA%\Android\Sdk\emulator\qemu\windows-x86_64\qemu-system-x86_64-headless.exe"
```

Pencereli emülatör için aynı klasördeki `qemu-system-x86_64.exe`'yi kullanın. (Bunu kendim denemedim; VMware için bildirilen yöntem budur.)

### 6. Asıl çözüm

Emülatörün açılışta bu çağrıyı kendisinin yapması, etkilenen bütün Windows kullanıcıları için sorunu çözer. Bu öneri [572278410 numaralı kayıtta](https://issuetracker.google.com/issues/572278410) Google'a iletildi; Windows tarafı da Feedback Hub üzerinden Microsoft'a bildirildi. Sizi de etkiliyorsa kayda **+1** vermek önceliklendirilmesine yardım eder.

### 7. Lisans

MIT. Bkz. [LICENSE](LICENSE).
