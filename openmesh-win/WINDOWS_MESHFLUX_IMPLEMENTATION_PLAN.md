# Implementation Status (Updated 2026-02-23)

## Phase Progress

- [x] Phase 0: Baseline setup and project structure (implemented)
- [x] Phase 1: Core minimum runnable loop (implemented, tested)
- [x] Phase 2: Profile load + dynamic routing rule injection (implemented, tested)
- [x] Phase 3: Action alignment (`reload` / `urltest` / `select_outbound`) (implemented, tested)
- [x] Phase 4: Realtime status channel (runtime metrics + outbound groups + connection list/filter/sort/close) (implemented, tested)
- [x] Phase 5: WinForms tray UX alignment with MeshFluxMac (implemented, tested)
- [ ] Phase 6: Wallet + x402 integration
- [ ] Phase 7: Installer + system integration
- [ ] Phase 8: Stability hardening + release

## Verification Notes

- Build passed: `dotnet build openmesh-win/openmesh-win.sln` (0 errors, 0 warnings)
- Phase 3 action flow passed: `reload -> status -> urltest -> select_outbound -> status`
- Phase 4 action flow passed:
  - `status` runtime metrics update over time
  - `connections` supports list/filter/sort
  - `close_connection` removes selected connection successfully
- UI smoke passed: `OpenMeshWin.exe` starts successfully
- Phase 5 UI flow passed: Tray Connect/Disconnect labels + Dashboard/Market/Settings tabs + Node/Traffic detail windows available

---
# OpenMesh Windows 瀹炴柦鎬昏鍒掞紙瀵归綈 MeshFluxMac锛?
## 1. 鐩爣涓庤寖鍥?
### 1.1 鐩爣

鍦?`openmesh-win` 涓嬪疄鐜颁竴涓?Windows 鎵樼洏搴旂敤锛屽姛鑳戒笌 `openmesh-apple/MeshFluxMac + vpn_extension_macos` 瀵归綈锛屽寘鍚細

- VPN 鍚仠涓庣姸鎬佺鐞?- 鍩轰簬 profile 鐨勯厤缃姞杞戒笌鐑噸杞?- 鍔ㄦ€佽鍒欙紙`routing_rules.json`锛夋敞鍏?- 鍑虹珯鑺傜偣 URLTest 涓庤妭鐐瑰垏鎹紙select outbound锛?- 杩炴帴/娴侀噺/鍒嗙粍鐘舵€佸睍绀?- 鎵樼洏鑿滃崟涓诲叆鍙?+ 寮圭獥寮忕鐞嗙晫闈?- 閽卞寘/浣欓/x402 鑳藉姏瀵归綈 `go-cli-lib/interface`

### 1.2 闈炵洰鏍囷紙绗竴闃舵涓嶅仛锛?
- 100% 澶嶅埢 SwiftUI 鍔ㄧ敾缁嗚妭锛堝厛鍋氳瑙夊拰浜や簰绛変环锛?- 涓€娆℃€у仛鍏ㄩ噺甯傚満鍚庣鏀归€狅紙鍏堝吋瀹圭幇鏈?profile/provider 鏂囦欢缁撴瀯锛?- 鐩存帴鍦?WinForms 鍐呭祵 GoMobile 鍔ㄦ€佸簱锛堝鏉傚害鍜岀ǔ瀹氭€ч闄╅珮锛?
## 2. 鐜扮姸鍒嗘瀽锛堝熀浜庡綋鍓嶄唬鐮侊級

### 2.1 `openmesh-apple/vpn_extension_macos` 鐨勬牳蹇冭兘鍔?
鍙傝€冿細

- `openmesh-apple/vpn_extension_macos/PacketTunnelProvider.swift`
- `openmesh-apple/vpn_extension_macos/LibboxSupport.swift`
- `openmesh-apple/vpn_extension_macos/DynamicRoutingRules.swift`
- `openmesh-apple/vpn_extension_macos/Info.plist`
- `openmesh-apple/vpn_extension_macos/vpn_extension_macos.entitlements`

宸插疄鐜板苟闇€瑕佸湪 Windows 瀵归綈鐨勫叧閿偣锛?
- 鐢熷懡鍛ㄦ湡锛歚startTunnel` / `stopTunnel` / `sleep` / `wake`
- 鍚姩椤哄簭锛歚Setup -> CommandServer.start -> NewService -> Service.start -> setService`
- 閰嶇疆鍏ュ彛锛氫弗鏍兼寜 selected profile 璇诲彇锛屼笉璧伴殣寮?fallback
- 閰嶇疆琛ヤ竵锛氬姩鎬佽鍒欐敞鍏ャ€乺outing mode patch銆乮ncludeAllNetworks 鍏煎鎬ф牎楠?- IPC 娑堟伅锛歚reload`銆乣urltest`銆乣select_outbound`
- 鍛戒护闈細鐘舵€?鍒嗙粍/杩炴帴锛堥€氳繃 command client锛?- 蹇冭烦鑷潃锛氫富绋嬪簭蹇冭烦涓㈠け 3 娆″悗涓诲姩鍋滈毀閬?- tun 鎵撳紑涓庣郴缁熺綉缁滆缃紪鎺掞紙IPv4/IPv6 route銆丏NS銆丳roxy锛?
瑙傚療鍒扮殑瀹炵幇鐗瑰緛锛圵indows 涔熷缓璁繚鐣欙級锛?
- 鏈嶅姟鍚姩鍜岄噸杞介兘鍦ㄤ笓鐢ㄤ覆琛岄槦鍒楋紝閬垮厤绔炴€?- 閰嶇疆瑙ｆ瀽閲囩敤鈥滃鏉?JSON锛堝幓娉ㄩ噴銆佸幓灏鹃€楀彿锛夆€濈瓥鐣ワ紝鍏煎閰嶇疆鏉ユ簮宸紓
- 涓?UI 鐨勪氦浜掑敖閲忛€氳繃 JSON action锛岄伩鍏?UI 鐩存帴鎸佹湁搴曞眰瀵硅薄

### 2.2 `go-cli-lib` 鐨勬牳蹇冭兘鍔?
鍙傝€冿細

- `go-cli-lib/interface/wallet.go`
- `go-cli-lib/interface/app_lib.go`
- `go-cli-lib/interface/vpn.go`
- `go-cli-lib/interface/vpn_darwin.go`
- `go-cli-lib/interface/vpn_ios.go`
- `go-cli-lib/interface/vpn_android.go`
- `go-cli-lib/go.mod`

宸插疄鐜板彲澶嶇敤鑳藉姏锛?
- 閽卞寘锛氱敓鎴愬姪璁拌瘝銆丅IP44 娲剧敓銆乲eystore 鍔犺В瀵?- 閾句笂浣欓锛歎SDC锛圔ase 涓荤綉/娴嬭瘯缃戯級
- x402 鏀粯

鐜扮姸缂哄彛锛?
- VPN 瀵瑰 API 鍦?`interface` 灞傚熀鏈槸鍗犱綅閫昏緫锛坕OS/Android锛夋垨婕旂ず绾ч€昏緫锛坉arwin锛?- 灏氭棤 `windows` build-tag 鐨?VPN 瀹炵幇鏂囦欢
- 浣嗕緷璧栧凡鍖呭惈 Windows 鐩稿叧缁勪欢锛坄wintun`銆乣wireguard/windows`銆乣go-winio`锛夛紝璇存槑鎶€鏈矾绾垮彲琛?
## 3. 鏋舵瀯缁撹锛圵indows 瀵圭瓑璁捐锛?
## 3.1 杩涚▼妯″瀷锛堝榻愨€滀富 App + 鎵╁睍鈥濓級

寤鸿閲囩敤涓夊眰锛?
- `OpenMeshWin.exe`锛圵inForms 鎵樼洏 UI锛岀敤鎴锋€侊級
- `openmesh-win-core.exe`锛圙o 鏍稿績杩涚▼锛岃礋璐?sing-box/libbox銆侀厤缃€佸懡浠わ級
- `openmesh-win-service.exe`锛圵indows Service 澶栧３锛屽彲閫変絾寮虹儓寤鸿锛岀敤浜庢彁鏉冨拰寮€鏈哄父椹伙級

鐞嗙敱锛?
- 瀵归綈 macOS 鐨勨€滀富绋嬪簭 + 鎵╁睍鈥濋殧绂绘ā鍨?- VPN/TUN/璺敱鎿嶄綔鍦?Windows 閫氬父闇€瑕佹洿楂樻潈闄?- UI 宕╂簝涓嶅簲瀵艰嚧闅ч亾鏍稿績绔嬪嵆閫€鍑?
## 3.2 閫氫俊妯″瀷

- UI <-> Core锛歂amed Pipe JSON-RPC锛堟湰鏈猴級
- Service <-> Core锛氳繘绋嬫帶鍒?+ 鍋ュ悍妫€鏌ワ紙鎴栧悓涓€杩涚▼锛?- 淇濇寔 action 鍗忚鍜岃嫻鏋滀晶涓€鑷达紝浼樺厛澶嶇敤锛?  - `reload`
  - `urltest`
  - `select_outbound`
  - 琛ュ厖 Windows 蹇呰 action锛歚start_vpn`銆乣stop_vpn`銆乣status`銆乣groups`銆乣connections`

## 3.3 鐩綍涓庢暟鎹ā鍨嬶紙瀵归綈 FilePath锛?
寤鸿锛?
- 鍏变韩鐩綍锛歚%ProgramData%\OpenMesh\shared`
- 宸ヤ綔鐩綍锛歚%ProgramData%\OpenMesh\work`
- 缂撳瓨鐩綍锛歚%ProgramData%\OpenMesh\cache`
- 閰嶇疆鐩綍锛歚%ProgramData%\OpenMesh\configs`
- Provider 鐩綍锛歚%ProgramData%\OpenMesh\MeshFlux\providers\<provider_id>\`
- 蹇冭烦鏂囦欢锛歚%ProgramData%\OpenMesh\MeshFlux\app_heartbeat`

杩欐牱鍙互鐩存帴澶嶇敤鑻规灉渚х殑 provider/rules 鏂囦欢缁勭粐鏂瑰紡銆?
## 4. 鍔熻兘鏄犲皠锛圓pple -> Windows锛?
| Apple 缁勪欢 | 褰撳墠鑱岃矗 | Windows 瀵瑰簲 |
|---|---|---|
| `PacketTunnelProvider` | VPN 鐢熷懡鍛ㄦ湡 + 閰嶇疆瑙ｆ瀽 + IPC action | `openmesh-win-core` 鐨?`TunnelController` + `ActionServer` |
| `LibboxSupport` | Tun 鎵撳紑銆佺綉缁滃弬鏁般€侀粯璁ゆ帴鍙ｇ洃鎺?| `WinTunAdapter` + `RouteManager` + `DnsManager` |
| `DynamicRoutingRules` | 璇诲彇/瑙勮寖鍖栬鍒欏苟娉ㄥ叆 route.rules | `rules` 鍖咃紙Go锛夊鍒诲悓閫昏緫 |
| `AppHeartbeatWriter` + extension heartbeat check | 涓荤▼搴忓瓨娲诲崗鍚?| UI 鍐欏績璺筹紝Core 璇诲績璺冲苟鑷仠 |
| `StatusCommandClient/GroupCommandClient/ConnectionCommandClient` | 鑿滃崟鐣岄潰瀹炴椂鏁版嵁婧?| WinForms `CoreClient`锛圥ipe 璁㈤槄锛?|
| `MenuBarExtra` UI | 鎵樼洏鍏ュ彛銆佽妭鐐圭鐞嗐€佹祦閲忚鍥?| NotifyIcon + 涓诲脊绐?Form + 娴姩瀛愮獥浣?|
| `go-cli-lib/interface/wallet.go` | 閽卞寘/浣欓/x402 | 鐩存帴鍦?Core 杩涚▼澶嶇敤 |

## 5. 鏍稿績妯″潡璁捐锛圵indows锛?
## 5.1 Go Core锛堝缓璁斁鍦?`go-cli-lib/cmd/openmesh-win-core`锛?
妯″潡鎷嗗垎寤鸿锛?
- `internal/core/bootstrap.go`
- `internal/core/tunnel_controller.go`
- `internal/core/config_resolver.go`
- `internal/core/config_patch.go`
- `internal/core/routing_rules.go`
- `internal/core/action_server_pipe.go`
- `internal/core/status_stream.go`
- `internal/core/heartbeat_guard.go`
- `internal/wallet/service.go`锛堝鐢?`interface/wallet.go`锛?
鍏抽敭琛屼负锛?
- 鍚姩椤哄簭涓ユ牸涓茶锛岄噸杞借矾寰勫拰鑻规灉渚т竴鑷?- `resolveConfig` 娴佹按绾匡細
  - 璇?selected profile
  - provider 瑙勫垯娉ㄥ叆锛坄routing_rules.json`锛?  - 搴旂敤 routing mode patch锛堜繚鐣?raw profile 璇箟锛?  - 鏍￠獙 tun 鍙傛暟鍏煎鎬?- action 鍏煎鑻规灉渚?payload锛屼究浜庢湭鏉ョ粺涓€鎺у埗闈?
## 5.2 Windows VPN 瀛愮郴缁?
浼樺厛璺嚎锛?
- 閲囩敤 sing-box 鐨?`tun` inbound + `wintun`
- Go Core 缁熶竴绠＄悊锛?  - 铏氭嫙缃戝崱寤虹珛/閲婃斁
  - 璺敱娉ㄥ叆/鍥炴粴
  - DNS 璁剧疆/鍥炴粴
  - 鍙€夌郴缁熶唬鐞嗗紑鍏?
闇€瑕佹槑纭殑宸ョ▼浜嬪疄锛?
- 棣栨瀹夎/椹卞姩闃舵闇€瑕佺鐞嗗憳鏉冮檺
- 鑻ヤ娇鐢?Windows Service锛屾牳蹇冭繘绋嬫潈闄愬拰鍥炴粴鑳藉姏鏇寸ǔ瀹?
## 5.3 WinForms 鎵樼洏搴旂敤

缁勪欢寤鸿锛?
- `TrayBootstrap`锛歂otifyIcon銆佸彸閿彍鍗曘€佺敓鍛藉懆鏈?- `MainPanelForm`锛氭墭鐩樹富寮圭獥锛堝榻?macOS 鑿滃崟绐楋級
- `NodePickerForm`锛氳妭鐐硅鎯呭拰閫夋嫨
- `TrafficForm`锛氭祦閲忓浘鍜岀疮璁″€?- `CoreClient`锛歅ipe RPC + 璁㈤槄
- `StateStore`锛歎I 鐘舵€佸綊涓€鍖栵紙杩炴帴鎬併€佸綋鍓?profile銆佸垎缁勩€佽妭鐐癸級

瑙嗚/浜や簰瀵归綈鐐癸紙鏉ヨ嚜 MeshFluxMac锛夛細

- 鍥炬爣鐘舵€侊細`mesh_on`/`mesh_off`
- 涓诲叆鍙ｅ搴﹀拰瀵嗗害鎺ヨ繎锛坢ac 绾?420x520锛?- 椤堕儴涓?tab锛欴ashboard / Market / Settings
- 钃濋潚鑹叉笎鍙樿儗鏅?+ 鐜荤拑鍗＄墖 + 鐘舵€佽壊锛堢豢/榛?绾級
- 鎻愪緵鐙珛寮圭獥锛氳妭鐐硅鎯呫€佹祦閲忚鎯?
## 5.4 閽卞寘涓庢敮浠?
澶嶇敤 `go-cli-lib/interface/wallet.go` 鐨勬柟娉曪細

- `GenerateMnemonic12`
- `CreateEvmWallet`
- `DecryptEvmWallet`
- `GetTokenBalance`
- `MakeX402Payment`

瀹夊叏钀藉湴锛?
- keystore 鏂囦欢浠呭瓨瀵嗘枃
- UI 杈撳叆瀵嗙爜涓嶈惤鐩?- 鍙€夋帴鍏?DPAPI 鍋氫簩娆′繚鎶?
## 6. 鍒嗛樁娈靛疄鏂借鍒掞紙瀹屾暣锛?
## Phase 0锛氬熀绾夸笌鐩綍閲嶆瀯锛?-2 澶╋級

浜や粯锛?
- 鍦?`openmesh-win` 寤虹珛娓呮櫚缁撴瀯锛圲I/鏂囨。锛?- 鍦?`go-cli-lib` 鏂板缓 `cmd/openmesh-win-core` 楠ㄦ灦
- 鏄庣‘閰嶇疆鐩綍瑙勮寖鍜屽父閲忓畾涔?
楠屾敹锛?
- 宸ョ▼鑳藉悓鏃剁紪璇?C# UI 涓?Go Core skeleton

## Phase 1锛欳ore 鏈€灏忓彲杩愯锛?-4 澶╋級

浜や粯锛?
- Pipe server 寤虹珛
- `start_vpn` / `stop_vpn` / `status` action 鎵撻€?- Core 鍗曠嚎绋嬬敓鍛藉懆鏈熸帶鍒跺櫒

楠屾敹锛?
- UI 鍙€氳繃 Pipe 鎺у埗 Core 鍚仠锛屽苟寰楀埌鐘舵€佸洖鍖?
## Phase 2锛氶厤缃姞杞戒笌琛ヤ竵閾捐矾锛?-5 澶╋級

浜や粯锛?
- Profile 璇诲彇
- `routing_rules.json` 瑙ｆ瀽涓庢敞鍏ワ紙瀵归綈 `DynamicRoutingRules.swift`锛?- routing mode patch锛堝榻?`ConfigModePatch.swift`锛?- 閰嶇疆瀹芥澗瑙ｆ瀽锛堟敞閲?灏鹃€楀彿锛?
楠屾敹锛?
- 缁欏畾 profile + provider rules锛岀敓鎴愭湡鏈涚殑杩愯閰嶇疆 JSON
- 閲嶈浇鍚庤鍒欐棤閲嶅娉ㄥ叆

## Phase 3锛氬姩浣滃崗璁榻愶紙3-4 澶╋級

浜や粯锛?
- `reload` action
- `urltest` action
- `select_outbound` action
- 杈撳叆鏍￠獙锛坱ag 闀垮害銆佸瓧绗︺€佺┖鍊硷級

楠屾敹锛?
- 涓庤嫻鏋滀晶 action payload 鍏煎
- 鑺傜偣鍒囨崲鍦ㄨ繍琛屾€佸彲鐢熸晥

## Phase 4锛氬疄鏃剁姸鎬侀€氶亾锛?-6 澶╋級

浜や粯锛?
- 鐘舵€佹祦锛氳繛鎺ユ€併€佹祦閲忋€佸唴瀛樸€佸崗绋?- 鍒嗙粍娴侊細outbound groups + items + selected
- 杩炴帴娴侊細杩炴帴鍒楄〃銆佺瓫閫夈€佹帓搴忋€佸叧闂繛鎺?
楠屾敹锛?
- UI 鑳藉疄鏃舵覆鏌撲笁绫绘暟鎹紝鏂繛鍙嚜鍔ㄦ仮澶嶈闃?
## Phase 5锛歐inForms 鎵樼洏鐣岄潰锛?-7 澶╋級

浜や粯锛?
- NotifyIcon + 鎵樼洏鑿滃崟锛圤pen/Connect/Disconnect/Exit锛?- 涓诲脊绐椾笁 tab锛圖ashboard/Market/Settings锛?- 鑺傜偣绐楀彛銆佹祦閲忕獥鍙?- 椋庢牸涓?MeshFluxMac 涓昏瑙夊榻?
楠屾敹锛?
- 瀹屾暣浜や簰闂幆锛氳繛鎺ャ€佹祴閫熴€佸垏鑺傜偣銆佹煡鐪嬫祦閲忋€佷慨鏀硅缃?
## Phase 6锛氶挶鍖呬笌 x402 闆嗘垚锛?-4 澶╋級

浜や粯锛?
- Core 鏆撮湶閽卞寘鐩稿叧 action
- UI 澧炲姞鏈€灏忓叆鍙ｏ紙鍙厛鏀?Settings 鎴栫嫭绔嬬獥鍙ｏ級

楠屾敹锛?
- 鍔╄璇嶇敓鎴愩€侀挶鍖呭垱寤?瑙ｅ瘑銆佷綑棰濇煡璇€亁402 璋冪敤鍏ㄩ儴閫?
## Phase 7锛氬畨瑁呬笌绯荤粺闆嗘垚锛?-7 澶╋級

浜や粯锛?
- 瀹夎鍖咃紙寤鸿 WiX锛?- Core/Service 鑷惎鍔ㄧ瓥鐣?- Wintun 渚濊禆閮ㄧ讲
- 鍗歌浇鍥炴粴锛堣矾鐢便€丏NS銆佹湇鍔★級

楠屾敹锛?
- 鏂版満鍣ㄥ畨瑁呭悗鍙竴閿繛鎺?- 鍗歌浇鍚庢棤娈嬬暀缃戠粶閰嶇疆姹℃煋

## Phase 8锛氱ǔ瀹氭€т笌鍙戝竷锛?-7 澶╋級

浜や粯锛?
- 宕╂簝鎭㈠銆佹棩蹇楄疆杞€佸績璺冲畧鎶?- 绔埌绔洖褰掔敤渚?- 鍙戝竷鍊欓€夌増鏈紙RC锛?
楠屾敹锛?
- 杩炵画杩愯 24h 鏃犺祫婧愭硠婕?- 鏂綉/閲嶈繛/鐫＄湢鍞ら啋绛夊満鏅彲鎭㈠

## 7. 娴嬭瘯璁″垝

## 7.1 鍗曞厓娴嬭瘯锛圙o锛?
- `routing_rules` 瑙ｆ瀽锛坖son/simple/rules 涓夌褰㈡€侊級
- 閰嶇疆娉ㄥ叆鍘婚噸姝ｇ‘鎬?- action 杈撳叆鏍￠獙
- 閽卞寘/鏀粯鏍稿績閫昏緫鍥炲綊

## 7.2 闆嗘垚娴嬭瘯锛圙o + Windows锛?
- start/stop/reload 椤哄簭绋冲畾鎬?- URLTest + select_outbound 鍥炶矾
- route/DNS 娉ㄥ叆涓庡洖婊?- 蹇冭烦澶辫仈鑷姩鍋滈毀閬?
## 7.3 UI 鑷姩鍖?鍗婅嚜鍔ㄥ洖褰?
- 鎵樼洏鑿滃崟鍏抽敭璺緞
- 杩炴帴鎬佸垏鎹㈣瑙夊弽棣?- 鑺傜偣閫夋嫨鍚庣姸鎬佷竴鑷存€?- 寮傚父寮圭獥涓庨敊璇彁绀?
## 7.4 楠屾敹鍦烘櫙锛堝繀椤婚€氳繃锛?
- 棣栨瀹夎 -> 杩炴帴鎴愬姛
- 鍒囨崲 profile -> reload 鐢熸晥
- 鍒囨崲鑺傜偣 -> 鍑哄彛鍙樺寲鍙娴?- 鍏抽棴涓荤獥浣撳悗绋嬪簭椹荤暀鎵樼洏
- 浠庢墭鐩橀€€鍑哄悗 Core 浼橀泤鍋滄

## 8. 鍏抽敭椋庨櫓涓庡绛?
## 8.1 椹卞姩涓庢潈闄愰闄?
- 椋庨櫓锛歐intun/璺敱鎿嶄綔闇€瑕佺鐞嗗憳鏉冮檺
- 瀵圭瓥锛歋ervice 妯″紡鎵樺簳锛涘畨瑁呮椂鏉冮檺鏍￠獙锛涘け璐ュ洖婊氳剼鏈?
## 8.2 Core 涓?UI 杩涚▼瑙ｈ€︿笉瓒?
- 椋庨櫓锛歎I 宕╂簝瀵艰嚧闅ч亾寮傚父
- 瀵圭瓥锛欳ore 鐙珛杩涚▼ + 蹇冭烦绾︽潫锛屽崗璁寲閫氫俊

## 8.3 閰嶇疆婧愪笉瑙勮寖

- 椋庨櫓锛氶厤缃惈娉ㄩ噴銆佸熬閫楀彿瀵艰嚧 JSON 瑙ｆ瀽澶辫触
- 瀵圭瓥锛氬鍒昏嫻鏋滀晶瀹芥澗瑙ｆ瀽绛栫暐骞跺姞娴嬭瘯

## 8.4 杩炴帴娴?鍒嗙粍娴佺珵鎬?
- 椋庨櫓锛氶噸杩炴椂璁㈤槄閿欎贡鎴栫姸鎬佹棫鍊艰鐩?- 瀵圭瓥锛氱粺涓€鐘舵€佺増鏈彿锛涢噸杩炲悗鍏ㄩ噺蹇収 + 澧為噺娴?
## 8.5 瀹夊叏椋庨櫓锛堢閽?鏀粯锛?
- 椋庨櫓锛氭晱鎰熶俊鎭硠闇?- 瀵圭瓥锛氬瘑鏂囧瓨鍌?+ 杩涚▼鍐呮渶鐭┗鐣?+ 鏃ュ織鑴辨晱

## 9. 浠ｇ爜钀藉湴寤鸿锛堢洰褰曪級

寤鸿鏂板锛堢ず渚嬶級锛?
- `go-cli-lib/cmd/openmesh-win-core/main.go`
- `go-cli-lib/internal/wincore/...`
- `openmesh-win/src/OpenMeshWin.CoreClient/...`
- `openmesh-win/src/OpenMeshWin.UI/...`
- `openmesh-win/docs/`锛堝悗缁媶鍒嗗瓙璁捐鏂囨。锛?
褰撳墠浠撳簱浣犲凡缁忔湁锛?
- `openmesh-win/OpenMeshWin.csproj`
- `openmesh-win/openmesh-win.sln`

鍙湪姝ゅ熀纭€涓婇€愭閲嶆瀯锛屼笉褰卞搷鐜版湁 WinForms 鍚姩鑳藉姏銆?
## 10. 棣栨鎵ц椤哄簭锛堝缓璁級

1. 鍏堝仛 Phase 0 + Phase 1锛屽敖蹇舰鎴愨€滃彲杩為€氱殑 UI <-> Core鈥濇渶灏忛棴鐜€?2. 鍐嶅仛 Phase 2 + Phase 3锛屾妸琛屼负瀵归綈鍒拌嫻鏋滄墿灞曪紙reload/urltest/select_outbound锛夈€?3. Phase 4 浠ュ悗鍐嶆帹 UI 椋庢牸銆佸競鍦哄拰閽卞寘鎵╁睍锛岄伩鍏嶅墠鏈?UI 杩斿伐銆?
杩欐潯椤哄簭鑳芥渶蹇毚闇?Windows 缃戠粶鏍堝拰鏉冮檺闂锛岄檷浣庡悗鏈熻繑宸ユ垚鏈€?



