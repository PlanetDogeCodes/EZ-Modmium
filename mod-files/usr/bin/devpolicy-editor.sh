#!/bin/bash
# written by mariah carey

source /root/.bashrc # to get $EDITOR
jsonFile="/usr/local/share/policy-test-tool/dump.json"
DEVINSTALL_FILE="/mnt/stateful_partition/.devinstall_complete"
DEVPOL_FILE="/mnt/stateful_partition/.devpol_setup"

fail(){
  stty echo 2>/dev/null || true
  tput cnorm 2>/dev/null || true
  echo -e "$1"
  sleep 3
  exit 1
}

stty -echo
tput civis
clear

source /usr/lib/libmosh.sh

if [[ ! -f $DEVPOL_FILE ]] || [[ ! -d /usr/local/share/policy-test-tool ]]; then
  mkdir -p /usr/local/share
  rm -rf /usr/local/share/policy-test-tool

  source /etc/profile # emerge breaks without this
  echo -e "${B}Installing required dependencies...${N}"

  if [[ ! -f $DEVINSTALL_FILE ]]; then
    printf 'y\n\nn' | dev_install --reinstall || fail "${R}Could not install dependencies. Connect to the internet first.${N}"
    touch $DEVINSTALL_FILE
  fi

  ldconfig # emerge breaks without this too
  emerge cryptography nano pyyaml protobuf-python

  cp -r /usr/share/.policy-test-tool /usr/local/share/policy-test-tool
  touch $DEVPOL_FILE
fi
if [[ ! -f "$jsonFile" ]]; then
  cp -r /usr/share/.policy-test-tool /usr/local/share/policy-test-tool
  cd /usr/local/share/policy-test-tool || exit 1
  ldconfig
  echo -e "${B}Dumping device policy to json...${N}"
  python devpol.py --dump --input $(ls /var/lib/devicesettings/policy.* | sort -V | tail -n 1) --output dump.json
  echo -e "${G}Done! Starting editor...${N}"
  sleep 2
  stty -echo
  tput civis
  clear
fi
cd /usr/local/share/policy-test-tool

# there's gotta be a better way to do this but whatever :sob:
RESTRICTIONS=(
  "DeviceGuestModeEnabled" "DeviceShowUserNamesOnSignin" "DeviceAllowNewUsers"
  "DeviceBlockDevmode" "DeviceUnaffiliatedCrostiniAllowed" "PluginVmAllowed"
  "DeviceUserAllowlist" "DeviceUserWhitelist" "DeviceFamilyLinkAccountsAllowed"
  "DeviceBorealisAllowed" "VirtualMachinesAllowed" "UnaffiliatedArcAllowed"
  "SupervisedUsersEnabled" "DeviceAllowRedeemChromeOsRegistrationOffers"
  "DeviceRestrictedManagedGuestSessionEnabled" "DeviceCrostiniArcAdbSideloadingAllowed"
  "DeviceLoginScreenExtensionManifestV2Availability" "DeviceExtensionsSystemLogEnabled"
  "DeviceEphemeralUsersEnabled" "DeviceDebugPacketCaptureAllowed"
)

REPORTING=(
  "ReportDeviceVersionInfo" "ReportDeviceActivityTimes" "ReportDeviceBootMode"
  "ReportDeviceNetworkInterfaces" "ReportDeviceUsers" "ReportDeviceHardwareStatus"
  "ReportDeviceSessionStatus" "ReportDeviceOsUpdateStatus" "ReportDeviceRunningKioskApp"
  "ReportDevicePowerStatus" "ReportDeviceStorageStatus" "ReportDeviceBoardStatus"
  "ReportDeviceCpuInfo" "ReportDeviceGraphicsStatus" "ReportDeviceCrashReportInfo"
  "ReportDeviceTimezoneInfo" "ReportDeviceMemoryInfo" "ReportDeviceBacklightInfo"
  "ReportDeviceBluetoothInfo" "ReportDeviceFanInfo" "ReportDeviceVpdInfo"
  "ReportDeviceSystemInfo" "ReportDevicePrintJobs" "ReportDeviceLoginLogout"
  "ReportDeviceAudioStatus" "ReportDeviceNetworkConfiguration" "ReportDeviceNetworkStatus"
  "ReportDeviceSecurityStatus" "ReportCRDSessions" "ReportDevicePeripherals"
  "DeviceReportNetworkEvents" "DeviceReportRuntimeCounters" "ReportUploadFrequency"
  "ReportDeviceNetworkTelemetryCollectionRateMs" "ReportDeviceAudioStatusCheckingRateMs"
  "ReportDeviceAppInfo" "ReportDeviceLocation" "ReportDeviceNetworkTelemetryEventCheckingRateMs"
  "ReportDeviceSignalStrengthEventDrivenTelemetry" "DeviceReportRuntimeCountersCheckingRateMs"
  "DeviceReportXDREvents" "EnableDeviceGranularReporting" "HeartbeatFrequency"
  "DeviceActivityHeartbeatCollectionRateMs" "DeviceActivityHeartbeatEnabled"
  "HeartbeatEnabled" "LogUploadEnabled"
)

ENTERPRISE=(
  "DeviceOpenNetworkConfiguration" "DevicePrinters" "DevicePrintersAccessMode"
  "DeviceLocalAccounts" "AllowKioskAppControlChromeVersion"
  "KioskCRXManifestUpdateURLIgnored" "DeviceLoginScreenDomainAutoComplete"
  "DeviceNativePrinters" "DeviceNativePrintersAccessMode" "DeviceNativePrintersBlacklist"
  "DeviceNativePrintersWhitelist" "DevicePrintersAllowlist" "DevicePrintersBlocklist"
  "DevicePrintingClientNameTemplate" "DeviceExternalPrintServers"
  "DeviceExternalPrintServersAllowlist" "DeviceHostnameTemplate"
  "DeviceHostnameUserConfigurable" "RequiredClientCertificateForDevice"
  "SystemProxySettings" "DeviceAllowEnterpriseRemoteAccessConnections"
  "DeviceWebBasedAttestationAllowedUrls" "DeviceLoginScreenAutoSelectCertificateForUrls"
  "DeviceLoginScreenSecurityKeyPermitAttestation" "DeviceLoginScreenContextAwareAccessSignalsAllowlist"
  "DeviceAuthenticationURLAllowlist" "DeviceAuthenticationURLBlocklist"
  "DeviceGpoCacheLifetime" "DeviceKerberosEncryptionTypes" "DeviceMachinePasswordChangeRate"
  "LoginVideoCaptureAllowedUrls" "DeviceLoginScreenExtensions"
  "DeviceLoginScreenInputMethods" "DeviceLoginScreenLocales"
  "ManagedGuestSessionPrivacyWarningsEnabled" "DeviceLocalAccountAutoLoginId"
  "DeviceLocalAccountAutoLoginDelay" "DeviceLocalAccountAutoLoginBailoutEnabled"
  "DeviceLocalAccountPromptForNetworkWhenOffline"
)

MISC=(
  "DeviceDataRoamingEnabled" "DeviceMetricsReportingEnabled" "ChromeOsReleaseChannel"
  "ChromeOsReleaseChannelDelegated" "SystemTimezone" "SystemTimezoneAutomaticDetection"
  "SystemUse24HourClock" "UptimeLimit" "AttestationEnabledForDevice"
  "AttestationForContentProtectionEnabled" "NetworkThrottlingEnabled"
  "DeviceEcryptfsMigrationStrategy" "DeviceWiFiFastTransitionEnabled"
  "DeviceAutoUpdateDisabled" "DeviceTargetVersionPrefix" "DeviceUpdateScatterFactor"
  "DeviceUpdateAllowedConnectionTypes" "DeviceUpdateHttpDownloadsEnabled"
  "RebootAfterUpdate" "DeviceRollbackToTargetVersion" "DeviceAutoUpdateTimeRestrictions"
  "DeviceWiFiAllowed" "DeviceAutoUpdateP2PEnabled" "DeviceUpdateStagingSchedule"
  "DeviceScheduledUpdateCheck" "DeviceTargetVersionSelector" "DeviceReleaseLtsTag"
  "DeviceRollbackAllowedMilestones" "DeviceChannelDowngradeBehavior"
  "DeviceExtendedAutoUpdateEnabled" "DeviceQuickFixBuildToken" "DeviceMinimumVersion"
  "DeviceMinimumVersionAueMessage" "MinimumRequiredChromeVersion"
  "DeviceScheduledReboot" "DeviceRebootOnShutdown" "DeviceRebootOnUserSignout"
  "DevicePowerwashAllowed" "DeviceRunAutomaticCleanupOnLogin" "AutoCleanUpStrategy"
  "DeviceShowLowDiskSpaceNotification" "DeviceAllowMGSToStoreDisplayProperties"
  "DeviceSecondFactorAuthentication" "DeviceLoginScreenGeolocationAccessLevel"
  "DeviceEphemeralNetworkPoliciesEnabled" "DeviceEncryptedReportingPipelineEnabled"
  "DeviceSystemWideTracingEnabled" "DevicePolicyRefreshRate" "DeviceVariationsRestrictParameter"
  "DeviceChromeVariations" "DeviceUserPolicyLoopbackProcessingMode"
  "DeviceKeylockerForStorageEncryptionEnabled" "DevicePciPeripheralDataAccessEnabled"
  "DeviceNativeClientForceAllowed" "DeviceQuirksDownloadEnabled"
  "DeviceHardwareVideoDecodingEnabled" "DeviceUserInitiatedFirmwareUpdatesEnabled"
  "DeviceUserInitiatedFlexSystemFirmwareUpdatesEnabled" "DeviceFlexArcPreloadEnabled"
  "DeviceFlexHwDataForProductImprovementEnabled"
  "DeviceArcDataSnapshotHours" "ChromadToCloudMigrationEnabled"
  "DeviceTransferSAMLCookies" "DeviceAutofillSAMLUsername"
  "DeviceLoginScreenIsolateOrigins" "DeviceLoginScreenSitePerProcess"
  "DeviceLoginScreenPreferSlowCiphers" "DeviceLoginScreenPreferSlowKexAlgorithms"
  "DeviceLoginScreenWebHidAllowDevicesForUrls" "DeviceLoginScreenWebUsbAllowDevicesForUrls"
  "DeviceLoginScreenPowerManagement" "DeviceWeeklyScheduledSuspend"
  "DeviceRestrictionSchedule" "DevicePowerPeakShiftEnabled"
  "DevicePowerPeakShiftBatteryThreshold" "DevicePowerPeakShiftDayConfig"
  "DeviceAdvancedBatteryChargeModeEnabled" "DeviceAdvancedBatteryChargeModeDayConfig"
  "DeviceBatteryChargeMode" "DeviceBatteryChargeCustomStartCharging"
  "DeviceBatteryChargeCustomStopCharging" "DevicePowerBatteryChargingOptimization"
  "DeviceBootOnAcEnabled" "DeviceUsbPowerShareEnabled" "DeviceChargingSoundsEnabled"
  "DeviceLowBatterySoundEnabled" "DeviceAllowBluetooth" "DeviceAllowedBluetoothServices"
  "DeviceBluetoothJustWorksPairingEnabled" "DeviceWilcoDtcAllowed"
  "DeviceWilcoDtcConfiguration" "DeviceSystemAecEnabled" "DeviceDisplayResolution"
  "DisplayRotationDefault" "DeviceDockMacAddressSource" "DeviceWallpaperImage"
  "CastReceiverName" "DeviceScreensaverLoginScreenEnabled"
  "DeviceScreensaverLoginScreenIdleTimeoutSeconds"
  "DeviceScreensaverLoginScreenImageDisplayIntervalSeconds"
  "DeviceScreensaverLoginScreenImages" "DeviceLoginScreenShowOptionsInSystemTrayMenu"
  "DeviceLoginScreenSystemInfoEnforced" "DeviceDlcPredownloadList" "ExtensionCacheSize"
  "DevicePostQuantumKeyAgreementEnabled" "DeviceHindiInscriptLayoutEnabled"
  "DeviceSwitchFunctionKeysBehaviorEnabled" "DeviceExtendedFkeysModifier"
  "DeviceI18nShortcutsEnabled" "DeviceKeyboardBacklightColor"
  "DeviceLoginScreenAccessibilityShortcutsEnabled"
  "DeviceLoginScreenDefaultHighContrastEnabled" "DeviceLoginScreenDefaultLargeCursorEnabled"
  "DeviceLoginScreenDefaultScreenMagnifierType" "DeviceLoginScreenDefaultSpokenFeedbackEnabled"
  "DeviceLoginScreenDefaultVirtualKeyboardEnabled" "DeviceLoginScreenHighContrastEnabled"
  "DeviceLoginScreenLargeCursorEnabled" "DeviceLoginScreenMonoAudioEnabled"
  "DeviceLoginScreenSpokenFeedbackEnabled" "DeviceLoginScreenStickyKeysEnabled"
  "DeviceLoginScreenAutoclickEnabled" "DeviceLoginScreenCaretHighlightEnabled"
  "DeviceLoginScreenCursorHighlightEnabled" "DeviceLoginScreenDictationEnabled"
  "DeviceLoginScreenFaceGazeEnabled" "DeviceLoginScreenKeyboardFocusHighlightEnabled"
  "DeviceLoginScreenPrivacyScreenEnabled" "DeviceLoginScreenSelectToSpeakEnabled"
  "DeviceLoginScreenTouchVirtualKeyboardEnabled" "DeviceLoginScreenVirtualKeyboardEnabled"
  "DeviceLoginScreenScreenMagnifierType" "DeviceLoginScreenPrimaryMouseButtonSwitch"
  "DeviceLoginScreenPromptOnMultipleMatchingCertificates"
  "DeviceShowNumericKeyboardForPassword" "DeviceAuthDataCacheLifetime"
  "DeviceAuthenticationFlowAutoReloadInterval" "PluginVmLicenseKey"
  "LoginAuthenticationBehavior"
)

allowInput(){
  stty echo
  tput cnorm
  clear
}
disallowInput(){
  stty -echo
  tput civis
  clear
}

confirmOrCancel(){
  case ${currentType} in
    'string')
      if [[ ! $currentVal =~ ^[\{\[] ]]; then
        echo "Current value: ${currentVal}"
      fi
      ;;
    'number')
      echo "Current value: ${currentVal}"
      ;;
  esac
  echo -e "${D}(Press Enter to edit, Esc to cancel)${N}"
  read -rsn1 k
  [[ "$k" == $'\x1b' ]] && return 1
  return 0
}

editJsonValue(){
  local key="$1"
  local currentType=$(jq -r --arg k "$key" '.device[$k] | type' "$jsonFile")
  local currentVal=$(jq -r --arg k "$key" '.device[$k]' "$jsonFile")

  if [ "$currentType" == "boolean" ]; then
    local newVal="true"; [ "$currentVal" == "true" ] && newVal="false"
    jq --arg k "$key" --argjson v "$newVal" '.device[$k] = $v' "$jsonFile" > "${jsonFile}.tmp" && mv "${jsonFile}.tmp" "$jsonFile"
  elif [[ "$currentType" == "string" ]]; then
    if [[ "$currentVal" =~ ^[\{\[] ]] && echo "$currentVal" | jq . >/dev/null 2>&1; then
      allowInput
      echo -e "${Y}Editing compressed object for ${N}$key"
      confirmOrCancel || { disallowInput; return; }
      echo "$currentVal" | jq . > "/tmp/mosh_tmp.json"
      "${EDITOR:-nano}" "/tmp/mosh_tmp.json"
      if jq . "/tmp/mosh_tmp.json" &>/dev/null; then
        local minified=$(jq -c . "/tmp/mosh_tmp.json")
        jq --arg k "$key" --arg v "$minified" '.device[$k] = $v' "$jsonFile" > "${jsonFile}.tmp" && mv "${jsonFile}.tmp" "$jsonFile"
      else
        echo -e "${R}Invalid syntax, changes discarded.${N}"
        sleep 2
      fi
      rm -f "/tmp/mosh_tmp.json"
      disallowInput
    else
      allowInput
      echo -e "${B}Editing ${N}$key"
      confirmOrCancel || { disallowInput; return; }
      local newval
      read -p "Enter new value: " newval
      jq --arg k "$key" --arg v "$newval" '.device[$k] = $v' "$jsonFile" > "${jsonFile}.tmp" && mv "${jsonFile}.tmp" "$jsonFile"
      disallowInput
    fi
  elif [ "$currentType" == "number" ]; then
    allowInput
    echo -e "${B}Editing ${N}$key"
    confirmOrCancel || { disallowInput; return; }
    read -p "Enter new value: " newval
    jq --arg k "$key" --argjson v "$newval" '.device[$k] = $v' "$jsonFile" > "${jsonFile}.tmp" 2>/dev/null
    if [ $? -eq 0 ]; then mv "${jsonFile}.tmp" "$jsonFile"; fi
    disallowInput
  else
    allowInput
    echo -e "${Y}Warning: $key is a complicated object.${N}"
    confirmOrCancel || { disallowInput; return; }
    jq --arg k "$key" '.device[$k]' "$jsonFile" > "/tmp/mosh_tmp.json"
    "${EDITOR:-nano}" "/tmp/mosh_tmp.json"
    if jq . "/tmp/mosh_tmp.json" &>/dev/null; then
      jq --arg k "$key" --argjson v "$(< /tmp/mosh_tmp.json)" '.device[$k] = $v' "$jsonFile" > "${jsonFile}.tmp" && mv "${jsonFile}.tmp" "$jsonFile"
    else
      echo -e "${R}Invalid JSON syntax. Changes discarded.${N}"
      sleep 2
    fi
    rm -f "/tmp/mosh_tmp.json"
    disallowInput
  fi
}

submenu(){
  local title="$1"
  shift
  local keys=("$@")
  local subSelectedIndex=0
  local options=()

  loadData(){
    options=()
    for k in "${keys[@]}"; do
      local val=$(jq -r --arg k "$k" '.device[$k]' "$jsonFile")
      local vtype=$(jq -r --arg k "$k" '.device[$k] | type' "$jsonFile")
      local dispName="${k:0:28}"
      [[ ${#k} -gt 28 ]] && dispName="${dispName}.."
      if [ "$vtype" == "boolean" ]; then
        [[ "$val" == "true" ]] && options+=("[${G}ON${N}]  $dispName") || options+=("[${R}OFF${N}] $dispName")
      elif [ "$vtype" == "array" ] || [ "$vtype" == "object" ]; then
        options+=("[${Y}{..}${N}] $dispName")
      else
        if [[ "$vtype" == "string" && "$val" =~ ^[\{\[] ]] && echo "$val" | jq . >/dev/null 2>&1; then
          options+=("[${Y}{\"${N}] $dispName")
        else
          local dispVal="${val:0:12}"
          [[ ${#val} -gt 12 ]] && dispVal="${dispVal}.."
          options+=("[${B}${dispVal//$'\n'/ }${N}] $dispName")
        fi
      fi
    done
    options+=("<-- Back")
  }

  clear
  loadData
  while :; do
    local numOptions=${#options[@]}
    local termHeight=$(tput lines)
    local termWidth=$(tput cols)
    local maxRows=$((termHeight - 6))
    local colWidth=42
    local numCols=$((termWidth / colWidth))
    [[ $numCols -lt 1 ]] && numCols=1

    local itemsPerPage=$((maxRows * numCols))
    local currentPage=$((subSelectedIndex / itemsPerPage))
    local pageStart=$((currentPage * itemsPerPage))

    tput cup 0 0
    echo -e "${P}=== $title (Page $((currentPage + 1))) ===${N}"
    [[ $title == Reporting ]] && \
    echo -e "${B}NOTE: Changing device policies stops reporting to the Google Admin Console. Modifying these does nothing.${N}\n"
    for r in $(seq 0 $((maxRows - 1))); do
      tput cup $((r + 2)) 0
      for c in $(seq 0 $((numCols - 1))); do
        local idx=$((pageStart + r + (c * maxRows)))
        if [ $idx -lt $numOptions ]; then
          local out="${options[$idx]}"
          if [ $idx -eq $subSelectedIndex ]; then
            printf "\e[7m %-${colWidth}s \e[0m" "$out"
          else
            printf " %-${colWidth}s " "$out"
          fi
        fi
      done
      tput el
    done
    tput ed

    read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.05 keyseq
      while read -rsn1 -t 0.01 _; do :; done
      [[ -z "$keyseq" ]] && break
      case "$keyseq" in
        '[A') subSelectedIndex=$(((subSelectedIndex - 1 + numOptions) % numOptions)) ;;
        '[B') subSelectedIndex=$(((subSelectedIndex + 1) % numOptions)) ;;
        '[C') [[ $((subSelectedIndex + maxRows)) -lt $numOptions ]] && subSelectedIndex=$((subSelectedIndex + maxRows)) ;;
        '[D') [[ $((subSelectedIndex - maxRows)) -ge 0 ]] && subSelectedIndex=$((subSelectedIndex - maxRows)) ;;
      esac
    elif [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
      break
    elif [[ "$key" == "" ]]; then
      if [ $subSelectedIndex -eq $((numOptions - 1)) ]; then
        break
      else
        editJsonValue "${keys[$subSelectedIndex]}"
        loadData
        clear
      fi
    fi
  done
  clear
}

# ---------------------------------------------------------------------------
# EZ-Modmium: policy search (fuzzy, /-triggered)
# ---------------------------------------------------------------------------
# Builds a flat list of all policy names with their category, lets the user
# type a query, filters, and opens the editor for the selected match.
searchPolicies() {
  local query=""
  local -a all_keys=()
  local -a all_cats=()
  local cat k
  for cat in Restrictions Reporting Enterprise Misc; do
    case "$cat" in
      Restrictions) for k in "${RESTRICTIONS[@]}"; do all_keys+=("$k"); all_cats+=("$cat"); done ;;
      Reporting)   for k in "${REPORTING[@]}";   do all_keys+=("$k"); all_cats+=("$cat"); done ;;
      Enterprise)  for k in "${ENTERPRISE[@]}"; do all_keys+=("$k"); all_cats+=("$cat"); done ;;
      Misc)        for k in "${MISC[@]}";        do all_keys+=("$k"); all_cats+=("$cat"); done ;;
    esac
  done

  allowInput
  clear
  echo -e "${B}=== Policy Search ===${N}"
  echo -e "Type a policy name (or part of it). Esc to cancel."
  echo -ne "${G}Search: ${N}"
  read -r -e query
  if [[ -z "$query" ]]; then
    disallowInput
    return
  fi

  # Filter (case-insensitive)
  local -a matches=()
  local -a match_cats=()
  local i
  for i in "${!all_keys[@]}"; do
    if [[ "${all_keys[$i],,}" == *"${query,,}"* ]]; then
      matches+=("${all_keys[$i]}")
      match_cats+=("${all_cats[$i]}")
    fi
  done

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo -e "${R}No policies matched '$query'.${N}"
    sleep 1.5
    disallowInput
    return
  fi

  # Show matches and let user pick
  local sel=0
  while true; do
    clear
    echo -e "${B}=== Search results for '$query' (${#matches[@]} matches) ===${N}"
    echo -e "${D}(Up/Down to navigate, Enter to edit, Esc to cancel)${N}"
    echo
    local j
    for j in "${!matches[@]}"; do
      local val vtype
      val=$(jq -r --arg k "${matches[$j]}" '.device[$k]' "$jsonFile" 2>/dev/null)
      vtype=$(jq -r --arg k "${matches[$j]}" '.device[$k] | type' "$jsonFile" 2>/dev/null)
      local prefix="   "
      [[ $j -eq $sel ]] && prefix="${P}> ${N}"
      local vdisp="$val"
      [[ ${#val} -gt 30 ]] && vdisp="${val:0:30}.."
      echo -e "${prefix}[${match_cats[$j]:0:3}] ${matches[$j]} = ${B}${vdisp}${N}"
    done
    read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.05 keyseq
      case "$keyseq" in
        '[A') sel=$(((sel - 1 + ${#matches[@]}) % ${#matches[@]})) ;;
        '[B') sel=$(((sel + 1) % ${#matches[@]})) ;;
        '') break ;;
      esac
    elif [[ "$key" == "" ]]; then
      editJsonValue "${matches[$sel]}"
    fi
  done
  disallowInput
}

# ---------------------------------------------------------------------------
# EZ-Modmium: load a policy preset
# ---------------------------------------------------------------------------
PRESETS_DIR="${PRESETS_DIR:-/usr/share/modmium/presets}"

loadPreset() {
  # List available presets
  local -a preset_files=()
  local -a preset_names=()
  local -a preset_descs=()
  local f
  while IFS= read -r -d '' f; do
    preset_files+=("$f")
    preset_names+=("$(jq -r '._preset_name // "unnamed"' "$f" 2>/dev/null)")
    preset_descs+=("$(jq -r '._preset_description // ""' "$f" 2>/dev/null)")
  done < <(find "$PRESETS_DIR" -name '*.json' -print0 2>/dev/null)

  if [[ ${#preset_files[@]} -eq 0 ]]; then
    allowInput
    echo -e "${R}No presets found in $PRESETS_DIR${N}"
    sleep 2
    disallowInput
    return
  fi

  # Show preset picker
  local sel=0
  while true; do
    clear
    echo -e "${B}=== Load Preset ===${N}"
    echo -e "${D}(Up/Down to navigate, Enter to load, Esc to cancel)${N}"
    echo
    local i
    for i in "${!preset_files[@]}"; do
      local prefix="   "
      [[ $i -eq $sel ]] && prefix="${P}> ${N}"
      echo -e "${prefix}${preset_names[$i]}"
      [[ -n "${preset_descs[$i]}" ]] && echo -e "      ${D}${preset_descs[$i]:0:70}${N}"
    done
    read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.05 keyseq
      case "$keyseq" in
        '[A') sel=$(((sel - 1 + ${#preset_files[@]}) % ${#preset_files[@]})) ;;
        '[B') sel=$(((sel + 1) % ${#preset_files[@]})) ;;
        '') break ;;
      esac
    elif [[ "$key" == "" ]]; then
      # Apply the selected preset (merge into dump.json)
      local preset_file="${preset_files[$sel]}"
      local pname="${preset_names[$sel]}"
      allowInput
      echo -e "${B}Loading preset: $pname${N}"
      echo -e "${D}This will merge the preset's values into your current policy dump.${N}"
      echo -e "${D}Only the keys in the preset will be changed. Press Apply Policies after.${N}"
      echo
      read -p "Press Enter to continue, or Ctrl+C to cancel..."
      # Merge: for each key in the preset (except _preset_*), set it in dump.json
      local keys
      keys=$(jq -r 'keys[] | select(startswith("_preset_") | not)' "$preset_file" 2>/dev/null)
      local count=0
      while IFS= read -r k; do
        [[ -z "$k" ]] && continue
        # Determine type first, then extract the value with the right flag
        local vtype
        vtype=$(jq --arg k "$k" '.[$k] | type' "$preset_file" 2>/dev/null)
        if [[ "$vtype" == "string" ]]; then
          # Use -r to get the raw string (avoids double-escaping)
          local val
          val=$(jq -r --arg k "$k" '.[$k]' "$preset_file" 2>/dev/null)
          jq --arg k "$k" --arg v "$val" '.device[$k] = $v' "$jsonFile" > "${jsonFile}.tmp" && mv "${jsonFile}.tmp" "$jsonFile"
        else
          # For booleans/numbers/arrays/objects, use --argjson with the JSON form
          local val
          val=$(jq --arg k "$k" '.[$k]' "$preset_file" 2>/dev/null)
          jq --arg k "$k" --argjson v "$val" '.device[$k] = $v' "$jsonFile" > "${jsonFile}.tmp" && mv "${jsonFile}.tmp" "$jsonFile"
        fi
        count=$((count + 1))
      done <<< "$keys"
      echo -e "${G}Applied $count policy values from preset '$pname'.${N}"
      echo -e "${Y}Press Apply Policies (option 5 in main menu) to write them.${N}"
      sleep 2
      disallowInput
      break
    fi
  done
}

main_menu_logo(){
  echo -e "${B}MOSH device policy editor${N}"
  echo -e "Use arrows to navigate. Enter to select. Esc to go back."
}

mainMenuOptions=("1) Restrictions" "2) Reporting" "3) Enterprise Settings" "4) Misc" "5) Apply Policies" "6) Reset All Changes" "7) Search Policies" "8) Load Preset" "9) Exit")
mainSelectedIndex=0
mainNumOptions=${#mainMenuOptions[@]}

full_menu(){
  while :; do
    tput cup 0 0
    main_menu_logo
    echo ""
    for i in "${!mainMenuOptions[@]}"; do
      if [[ $i -eq $mainSelectedIndex ]]; then
        printf "\e[7m > %-40s \e[0m\n" "${mainMenuOptions[$i]}"
      else
        printf "   %-45s\n" "${mainMenuOptions[$i]}"
      fi
    done
    tput ed

    read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.05 keyseq
      while read -rsn1 -t 0.01 _; do :; done
      case "$keyseq" in
        '[A') mainSelectedIndex=$(((mainSelectedIndex - 1 + mainNumOptions) % mainNumOptions)) ;;
        '[B') mainSelectedIndex=$(((mainSelectedIndex + 1) % mainNumOptions)) ;;
      esac
    elif [[ "$key" =~ [1-9] ]]; then
      mainSelectedIndex=$((key - 1))
    elif [[ "$key" == "" ]]; then
      case $mainSelectedIndex in
        0) submenu "Restrictions" "${RESTRICTIONS[@]}" ;;
        1) submenu "Reporting" "${REPORTING[@]}" ;;
        2) submenu "Enterprise Settings" "${ENTERPRISE[@]}" ;;
        3) submenu "Misc Settings" "${MISC[@]}" ;;
        4)
          allowInput
          echo -e "${G}Applying device policies!${N}"
          python devpol.py "$jsonFile" && exit 0 || { sleep 2; disallowInput; } ;;
        5)
          allowInput
          echo -e "${Y}Reverting changes!${N}"
          pushd /var/lib/devicesettings &> /dev/null
          mv owner.key.bak.enterprise owner.key &> /dev/null
          local policyBackup=$(ls policy.*.bak.enterprise 2>/dev/null)
          [[ -n "$policyBackup" ]] && mv "$policyBackup" "${policyBackup%.bak.enterprise}" &> /dev/null
          popd &> /dev/null
          rm -rf $jsonFile
          echo -e "${G}Done!${N}"; sleep 2; restart ui; exit 0 ;;
        6) searchPolicies ;;
        7) loadPreset ;;
        8)
          exit 0 ;;
      esac
      clear
    fi
  done
}

full_menu
