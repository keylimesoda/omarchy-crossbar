import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import qs.services
import "MenuModel.js" as MenuModel

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"
  // Optional native Modern-XMB Vulkan + AVX-512 Wayland layer-shell underlay.
  // Auto-discovers modern_xmb on PATH / ~/.local/share/modern-xmb / ~/Modern-XMB and falls back
  // seamlessly to the built-in pure-QML shader ribbon when unavailable.
  property string xmbConfigPath: Quickshell.env("HOME") + "/.config/omarchy/crossbar.json"
  property bool useNativeBackend: true
  property string nativeBackendBin: ""
  property string modernXmbAssetsDir: ""
  property var discoveredQrcPresets: []
  property string nativeBackendQrc: ""
  property string xmbMonth: "auto"
  property string xmbTime: "auto"
  property real nativeBackendOpacity: 0.99
  property string xmbFontChoice: "rodin"
  property bool xmbClock24h: false
  property bool xmbPreviewActive: false
  readonly property bool effectiveNativeBackend: root.useNativeBackend
    && root.nativeBackendBin.length > 0
  property real waveTargetX: 0

  // One-shot startup probe to locate modern-moyou binary, optional asset directory, and
  // available .json (modern-moyou-theme/v1) / .qrc themes across plugin, user, and system dirs.
  Process {
    id: nativeEnvProbe
    running: true
    command: ["python3", "-c",
      "import glob,json,os,shutil,sys\n" +
      "plugin_themes=sys.argv[1]\n" +
      "home=os.path.expanduser('~')\n" +
      "env_dir=os.environ.get('MODERN_MOYOU_DIR') or os.environ.get('MODERN_XMB_DIR','')\n" +
      "bin_cands=[os.environ.get('MODERN_MOYOU_BIN',''),os.environ.get('MODERN_XMB_BIN','')," +
      "shutil.which('modern-moyou') or '',shutil.which('modern_xmb') or ''," +
      "os.path.join(home,'.local/bin/modern-moyou')," +
      "(os.path.join(env_dir,'build/modern-moyou') if env_dir else '')," +
      "os.path.join(home,'modern-moyou/build/modern-moyou')," +
      "os.path.join(home,'Modern-XMB/build/modern-moyou')," +
      "os.path.join(home,'Modern-XMB/build/modern_xmb')]\n" +
      "bin_path=next((p for p in bin_cands if p and os.path.isfile(p) and os.access(p,os.X_OK)),'')\n" +
      "asset_cands=[os.environ.get('MODERN_MOYOU_ASSETS',''),os.environ.get('MODERN_XMB_ASSETS','')," +
      "os.path.join(home,'.local/share/modern-moyou'),'/usr/share/modern-moyou'," +
      "os.path.join(home,'.local/share/modern-xmb'),'/usr/share/modern-xmb'," +
      "(os.path.join(env_dir,'assets') if env_dir else '')," +
      "os.path.join(home,'modern-moyou/assets')," +
      "os.path.join(home,'Modern-XMB/assets')]\n" +
      "assets_dir=next((d for d in asset_cands if d and os.path.isdir(d)),'')\n" +
      "patterns=[\n" +
      "  os.path.join(plugin_themes,'*.json'),\n" +
      "  os.path.join(home,'.local/share/modern-moyou/**/*.json'),\n" +
      "  os.path.join(home,'.local/share/modern-moyou/**/*.qrc'),\n" +
      "  '/usr/share/modern-moyou/themes/*.json',\n" +
      "  os.path.join(home,'modern-moyou/themes/*.json'),\n" +
      "  os.path.join(home,'Modern-XMB/themes/*.json'),\n" +
      "  os.path.join(assets_dir,'themes','*.json') if assets_dir else '',\n" +
      "  os.path.join(assets_dir,'qrc','*.qrc') if assets_dir else '',\n" +
      "]\n" +
      "seen=set(); themes=[]\n" +
      "for pat in patterns:\n" +
      "  if not pat: continue\n" +
      "  for p in sorted(glob.glob(pat,recursive=True)):\n" +
      "    rp=os.path.realpath(p)\n" +
      "    base=os.path.basename(p)\n" +
      "    if rp in seen or base in seen: continue\n" +
      "    seen.add(rp); seen.add(base)\n" +
      "    stem=os.path.splitext(base)[0]\n" +
      "    label=stem.replace('_',' ').replace('-',' ').title()\n" +
      "    if p.endswith('.json'):\n" +
      "      try:\n" +
      "        d=json.load(open(p))\n" +
      "        if d.get('schema')!='modern-moyou-theme/v1': continue\n" +
      "        if isinstance(d.get('name'),str) and d['name'].strip(): label=d['name'].strip()\n" +
      "      except Exception: continue\n" +
      "    themes.append({'id':stem,'label':label,'path':p})\n" +
      "themes.append({'id':'builtin','label':'Built-in (Procedural)','path':'builtin'})\n" +
      "print(json.dumps({'bin':bin_path,'assets':assets_dir,'qrcs':themes}))\n",
      Qt.resolvedUrl("themes").toString().replace(/^file:\/\//, "")
    ]
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var info = JSON.parse(line)
          root.nativeBackendBin = info.bin || ""
          root.modernXmbAssetsDir = info.assets || ""
          root.discoveredQrcPresets = info.qrcs || []
          if (!root.nativeBackendQrc && root.discoveredQrcPresets.length > 0) {
            var preferred = null
            for (var i = 0; i < root.discoveredQrcPresets.length; i++) {
              if (root.discoveredQrcPresets[i].id === "classic-silk") { preferred = root.discoveredQrcPresets[i].path; break }
            }
            if (!preferred) {
              for (var j = 0; j < root.discoveredQrcPresets.length; j++) {
                if (root.discoveredQrcPresets[j].id === "stock_ofw_lines") { preferred = root.discoveredQrcPresets[j].path; break }
              }
            }
            root.nativeBackendQrc = preferred || root.discoveredQrcPresets[0].path
          }
          if (root.rowsLoaded) root.rebuildItemsFromSources()
        } catch (e) {}
      }
    }
  }

  Process {
    id: nativeBgProcess
    running: root.effectiveNativeBackend && root.opened && root.rowsLoaded
    command: [
      root.nativeBackendBin,
      "--layer-shell",
      "--month", String(root.xmbMonth),
      "--time", String(root.xmbTime),
      "--opacity", String(root.nativeBackendOpacity),
      root.nativeBackendQrc || "builtin"
    ]
  }

  // Zero-fork persistent UNIX datagram bridge for modern-moyou's 32x16 particle flow-field wind
  // and live preview IPC (month / time / opacity / qrc).
  Process {
    id: nativeWindBridge
    running: root.effectiveNativeBackend && root.opened && root.rowsLoaded
    stdinEnabled: true
    command: ["python3", "-u", "-c",
      "import os,socket,sys\n" +
      "base=os.environ.get('XDG_RUNTIME_DIR','/tmp')\n" +
      "socks=[os.path.join(base,'modern-moyou-wind.sock'),os.path.join(base,'modern-xmb-wind.sock')]\n" +
      "s=socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM)\n" +
      "for line in sys.stdin:\n" +
      "  msg=line.strip().encode()\n" +
      "  if msg:\n" +
      "    for p in socks:\n" +
      "      try: s.sendto(msg,p); break\n" +
      "      except OSError: pass\n"
    ]
  }

  function sendNavWind(cmd) {
    if (root.effectiveNativeBackend && nativeWindBridge.running) {
      nativeWindBridge.write(cmd + "\n")
    }
  }

  FileView {
    id: xmbSettingsFile
    path: root.xmbConfigPath
    watchChanges: false
    printErrors: false
    onLoaded: root.loadXmbSettings(text())
  }

  Process {
    id: xmbSettingsSaveProc
  }

  function loadXmbSettings(rawText) {
    try {
      var cfg = JSON.parse(rawText || "{}")
      if (typeof cfg.qrc === "string" && cfg.qrc.length > 0) root.nativeBackendQrc = cfg.qrc
      if (typeof cfg.month === "string" && cfg.month.length > 0) root.xmbMonth = cfg.month
      if (typeof cfg.time === "string" && cfg.time.length > 0) root.xmbTime = cfg.time
      if (typeof cfg.opacity === "number" && cfg.opacity >= 0.05 && cfg.opacity <= 1.0) root.nativeBackendOpacity = cfg.opacity
      if (typeof cfg.font === "string" && cfg.font.length > 0) root.xmbFontChoice = cfg.font
      if (typeof cfg.clock24h === "boolean") root.xmbClock24h = cfg.clock24h
      if (typeof cfg.useNativeBackend === "boolean") root.useNativeBackend = cfg.useNativeBackend
      if (root.rowsLoaded) root.rebuildItemsFromSources()
    } catch (e) {}
  }

  function saveXmbSettings() {
    var payload = JSON.stringify({
      qrc: root.nativeBackendQrc,
      month: root.xmbMonth,
      time: root.xmbTime,
      opacity: root.nativeBackendOpacity,
      font: root.xmbFontChoice,
      clock24h: root.xmbClock24h,
      useNativeBackend: root.useNativeBackend
    }, null, 2) + "\n"
    xmbSettingsSaveProc.command = [
      "python3", "-c",
      "import os,sys; p=sys.argv[1]; os.makedirs(os.path.dirname(p),exist_ok=True); t=p+'.tmp'; open(t,'w').write(sys.argv[2]); os.replace(t,p)",
      root.xmbConfigPath, payload
    ]
    xmbSettingsSaveProc.running = true
  }

  function previewXmbAction(action) {
    if (!action || action.indexOf("xmb:") !== 0) return
    var parts = action.split(":")
    if (parts.length < 3) return
    var key = parts[1]
    var val = parts.slice(2).join(":")
    if (key === "qrc") { root.sendNavWind("theme " + val); root.xmbPreviewActive = true }
    else if (key === "month") { root.sendNavWind("month " + val); root.xmbPreviewActive = true }
    else if (key === "time") { root.sendNavWind("time " + val); root.xmbPreviewActive = true }
    else if (key === "opacity") { root.sendNavWind("opacity " + val); root.xmbPreviewActive = true }
  }

  function restoreXmbLiveState() {
    if (!root.xmbPreviewActive) return
    root.xmbPreviewActive = false
    root.sendNavWind("theme " + (root.nativeBackendQrc || "builtin"))
    root.sendNavWind("month " + root.xmbMonth)
    root.sendNavWind("time " + root.xmbTime)
    root.sendNavWind("opacity " + String(root.nativeBackendOpacity))
  }

  function applyXmbAction(action) {
    var parts = action.split(":")
    if (parts.length < 3) return
    var key = parts[1]
    var val = parts.slice(2).join(":")
    root.xmbPreviewActive = false
    if (key === "qrc") {
      root.nativeBackendQrc = val
      root.sendNavWind("theme " + val)
    } else if (key === "month") {
      root.xmbMonth = val
      root.sendNavWind("month " + val)
    } else if (key === "time") {
      root.xmbTime = val
      root.sendNavWind("time " + val)
    } else if (key === "opacity") {
      var op = parseFloat(val)
      if (!isNaN(op) && op >= 0.05 && op <= 1.0) {
        root.nativeBackendOpacity = op
        root.sendNavWind("opacity " + String(op))
      }
    } else if (key === "font") {
      root.xmbFontChoice = val
    } else if (key === "clock24h") {
      root.xmbClock24h = (val === "true")
    } else if (key === "renderer") {
      root.useNativeBackend = (val === "native")
    }
    root.saveXmbSettings()
    root.rebuildItemsFromSources()
    root.goBack()
  }

  // Optional user-supplied PS3 system Latin fontsets (gracefully falls back to root.fontFamily).
  FontLoader {
    id: ps3FontRegular
    source: root.modernXmbAssetsDir ? ("file://" + root.modernXmbAssetsDir + "/fonts/SCE-PS3-RD-R-LATIN.TTF") : ""
  }
  FontLoader {
    id: ps3FontRounded
    source: root.modernXmbAssetsDir ? ("file://" + root.modernXmbAssetsDir + "/fonts/SCE-PS3-VR-R-LATIN.TTF") : ""
  }
  FontLoader {
    id: ps3FontPop
    source: root.modernXmbAssetsDir ? ("file://" + root.modernXmbAssetsDir + "/fonts/SCE-PS3-SR-R-LATIN.TTF") : ""
  }
  property real waveTargetY: 0
  property real waveVelX: 0
  property real waveVelY: 0
  property real waveVelXDot: 0
  property real waveVelYDot: 0
  property real particleParallaxX: 0
  property real particleParallaxY: 0

  Timer {
    interval: 16
    repeat: true
    running: panel.visible && (
      Math.abs(root.waveVelX) > 0.0002 || Math.abs(root.waveVelY) > 0.0002 ||
      Math.abs(root.waveVelXDot) > 0.0005 || Math.abs(root.waveVelYDot) > 0.0005 ||
      Math.abs(root.waveTargetX) > 0.0002 || Math.abs(root.waveTargetY) > 0.0002 ||
      Math.abs(root.particleParallaxY) > 0.0005
    )
    onTriggered: {
      // Critically damped 2nd-order spring (K=64, D=16 -> C1 smooth acceleration & settle)
      var dt = 0.016
      var K = 64.0
      var D = 16.0
      var ax = K * (root.waveTargetX - root.waveVelX) - D * root.waveVelXDot
      var ay = K * (root.waveTargetY - root.waveVelY) - D * root.waveVelYDot
      root.waveVelXDot += ax * dt
      root.waveVelYDot += ay * dt
      root.waveVelX += root.waveVelXDot * dt
      root.waveVelY += root.waveVelYDot * dt
      root.waveTargetX *= 0.90
      root.waveTargetY *= 0.90

      // Smoothly integrate horizontal parallax (persists) and vertical parallax (gently recenters)
      root.particleParallaxX += root.waveVelX * dt * 3.2
      root.particleParallaxY = root.particleParallaxY * 0.95 + root.waveVelY * dt * 2.0

      if (Math.abs(root.waveTargetX) <= 0.0002) root.waveTargetX = 0
      if (Math.abs(root.waveTargetY) <= 0.0002) root.waveTargetY = 0
      if (root.waveTargetX === 0 && Math.abs(root.waveVelX) <= 0.0002 && Math.abs(root.waveVelXDot) <= 0.0005) {
        root.waveVelX = 0; root.waveVelXDot = 0
      }
      if (root.waveTargetY === 0 && Math.abs(root.waveVelY) <= 0.0002 && Math.abs(root.waveVelYDot) <= 0.0005) {
        root.waveVelY = 0; root.waveVelYDot = 0
      }
      if (root.waveVelY === 0 && Math.abs(root.particleParallaxY) <= 0.0005) root.particleParallaxY = 0
    }
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  // PS3-inspired XMB surface. The host creates this layer-shell window on the
  // focused output, matching the behavior of the packaged Omarchy menu.
  PanelWindow {
    id: panel
    property bool fadeOutActive: false
    visible: (root.opened || fadeOutActive) && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Timer {
      id: panelFadeOutTimer
      interval: 200
      repeat: false
      onTriggered: panel.fadeOutActive = false
    }

      Connections {
      target: root
      function onOpenedChanged() {
        if (root.opened) {
          panelFadeOutTimer.stop()
          panel.fadeOutActive = false
          xmbFadeOutAnim.stop()
          card.opacity = 0.0
          card.scale = 0.985
          xmbFadeInAnim.restart()
        } else if (panel.visible) {
          xmbFadeInAnim.stop()
          panel.fadeOutActive = true
          xmbFadeOutAnim.restart()
          panelFadeOutTimer.restart()
        }
      }
    }

    // Compatibility hooks used by the retained menu/search model.
    property int cardTop: -1
    property int maxRowsHeight: -1
    function freezeCardTop() {}

    Image { id: xmbWaveAtlas;   source: "shaders/wave_atlas.png";     visible: false; smooth: false; mipmap: false }
    Image { id: xmbWaveNormals; source: "shaders/wave_normals.png";   visible: false; smooth: true;  mipmap: false }
    Image { id: xmbFresLut;     source: "shaders/freslut.png";        visible: false; smooth: true;  mipmap: false }
    Image { id: xmbNoiseTex;    source: "shaders/noise.png";          visible: false; smooth: true;  mipmap: false }
    Image { id: xmbCloudTex;    source: "shaders/particle_cloud.png"; visible: false; smooth: false; mipmap: false }

    // Offscreen 4x MSAA QML fallback scene (disabled when native Modern-XMB underlay is active).
    Item {
      id: xmbRawScene
      anchors.fill: parent
      visible: false
      layer.enabled: panel.visible && !root.effectiveNativeBackend
      layer.samples: 4
      layer.smooth: true
      layer.textureSize: Qt.size(Math.max(1, Math.round(width * 0.5)), Math.max(1, Math.round(height * 0.5)))

      ShaderEffect {
        id: xmbBackground
        anchors.fill: parent
        property color topColor: Qt.rgba(0.032, 0.115, 0.255, 1.0)
        property color bottomColor: Qt.rgba(0.008, 0.025, 0.070, 1.0)
        property vector2d resolution: Qt.vector2d(width, height)
        property real time: 0
        fragmentShader: "shaders/ps3_bg.frag.qsb"

        NumberAnimation on time {
          from: 0
          to: 1000
          duration: 1000000
          loops: Animation.Infinite
          running: panel.visible
        }
      }

      // Companion PS3 SPU cloth strip (incommensurate 113s period, lightweight 64x40 mesh).
      ShaderEffect {
        anchors.fill: parent
        blending: true
        mesh: GridMesh { resolution: Qt.size(64, 40) }
        property var atlas: xmbWaveAtlas
        property var normalMap: xmbWaveNormals
        property var fresLut: xmbFresLut
        property var noiseTex: xmbNoiseTex
        property color tint: Qt.rgba(0.76, 0.87, 1.0, 1.0)
        property vector2d resolution: Qt.vector2d(width, height)
        property real framePhase: 21
        property real alpha: 0.11
        property real scaleY: 1.26
        property real waveVelX: root.waveVelX * 0.7
        property real waveVelY: root.waveVelY * 0.7
        vertexShader: "shaders/ps3_cap.vert.qsb"
        fragmentShader: "shaders/ps3_cap.frag.qsb"

        NumberAnimation on framePhase {
          from: 21
          to: 85
          duration: 113000
          loops: Animation.Infinite
          running: panel.visible && !root.effectiveNativeBackend
        }
      }

      // Primary PS3 SPU cloth ribbon (96x64 mesh = 2.7x fewer vertices, smooth via Catmull-Rom + MSAA).
      ShaderEffect {
        id: xmbCapturedWave
        anchors.fill: parent
        blending: true
        mesh: GridMesh { resolution: Qt.size(96, 64) }
        property var atlas: xmbWaveAtlas
        property var normalMap: xmbWaveNormals
        property var fresLut: xmbFresLut
        property var noiseTex: xmbNoiseTex
        property color tint: Qt.rgba(0.88, 0.94, 1.0, 1.0)
        property vector2d resolution: Qt.vector2d(width, height)
        property real framePhase: 0
        property real alpha: 0.17
        property real scaleY: 1.15
        property real waveVelX: root.waveVelX
        property real waveVelY: root.waveVelY
        vertexShader: "shaders/ps3_cap.vert.qsb"
        fragmentShader: "shaders/ps3_cap.frag.qsb"

        NumberAnimation on framePhase {
          from: 0
          to: 64
          duration: 80000
          loops: Animation.Infinite
          running: panel.visible && !root.effectiveNativeBackend
        }
      }

      // RPCS3 draw-36 3D eye-space particle cloud (hover-around-home + 3D nav parallax).
      ShaderEffect {
        anchors.fill: parent
        blending: true
        property var cloudTex: xmbCloudTex
        property vector2d resolution: Qt.vector2d(Math.max(1, Math.round(width * 0.5)), Math.max(1, Math.round(height * 0.5)))
        property real time: xmbBackground.time
        property real parallaxX: root.particleParallaxX
        property real parallaxY: root.particleParallaxY
        fragmentShader: "shaders/ps3_particles.frag.qsb"
      }
    }

    // Quarter-res HDR glare bloom layer (disabled when hidden or native backend is active).
    MultiEffect {
      id: xmbBloomLayer
      source: xmbRawScene
      anchors.fill: parent
      visible: false
      blurEnabled: true
      blur: 1.0
      blurMax: 24
      autoPaddingEnabled: false
      layer.enabled: panel.visible && !root.effectiveNativeBackend
      layer.smooth: true
      layer.textureSize: Qt.size(Math.max(1, Math.round(width * 0.25)), Math.max(1, Math.round(height * 0.25)))
    }

    // Final FS_COMPOSITE filmic tone-map + glare blend (hidden when native Modern-XMB underlay is active).
    ShaderEffect {
      anchors.fill: parent
      visible: !root.effectiveNativeBackend
      opacity: 0.98
      property var sceneTex: xmbRawScene
      property var bloomTex: xmbBloomLayer
      property real bloomStrength: 0.85
      property real time: xmbBackground.time
      fragmentShader: "shaders/ps3_composite.frag.qsb"
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    Item {
      id: card
      anchors.fill: parent
      anchors.leftMargin: Math.max(48, panel.width * 0.065)
      anchors.rightMargin: Math.max(48, panel.width * 0.065)
      anchors.topMargin: 0
      anchors.bottomMargin: 0
      readonly property real categoryAnchorCenterX: categoryList.selectedCenterX
      opacity: 0.0

      // Authentic PS3 In-Game XMB summon/dismiss choreography:
      // 70 ms stagger behind the ribbon fade-in, then fade straight in place over 240 ms
      // with subtle 0.985 -> 1.0 settle; reverse smoothly over 180 ms on dismiss.
      SequentialAnimation {
        id: xmbFadeInAnim
        PauseAnimation { duration: 70 }
        ParallelAnimation {
          NumberAnimation { target: card; property: "opacity"; from: 0.0; to: 1.0; duration: 240; easing.type: Easing.OutCubic }
          NumberAnimation { target: card; property: "scale"; from: 0.985; to: 1.0; duration: 260; easing.type: Easing.OutCubic }
        }
      }
      NumberAnimation {
        id: xmbFadeOutAnim
        target: card
        property: "opacity"
        to: 0.0
        duration: 180
        easing.type: Easing.InCubic
      }

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Use compositor/Qt-provided deltas without adding a speed multiplier.
      // Touchpads report pixels while mouse wheels report angle units, so each
      // input type keeps its native scale and accumulates partial row steps.
      WheelHandler {
        id: menuWheel
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: panel.visible && !root.deleteConfirmOpen
        property real remainderY: 0
        property bool accumulatingPixels: false

        onEnabledChanged: {
          remainderY = 0
          accumulatingPixels = false
        }
        onWheel: function(event) {
          var usePixels = event.pixelDelta.y !== 0
          var delta = usePixels ? event.pixelDelta.y : event.angleDelta.y
          if (delta === 0) return

          if (remainderY !== 0 && accumulatingPixels !== usePixels)
            remainderY = 0
          accumulatingPixels = usePixels

          if (remainderY !== 0 && ((remainderY > 0) !== (delta > 0)))
            remainderY = 0
          remainderY += delta

          var stepSize = usePixels ? root.baseRowHeight : 120
          var steps = Math.floor(Math.abs(remainderY) / stepSize)
          if (steps === 0) {
            event.accepted = true
            return
          }

          var direction = remainderY > 0 ? -1 : 1
          remainderY -= (remainderY > 0 ? 1 : -1) * steps * stepSize
          root.select(direction * steps)
          event.accepted = true
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (root.dmenuActive) {
            if (root.handleDmenuKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Left && !root.filterText && root.activeMenu === "root") {
            root.selectCategory(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right && !root.filterText && root.activeMenu === "root") {
            root.selectCategory(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Left && !root.filterText) {
            if (root.activeMenuIsTopLevel()) root.selectCategory(-1)
            else if (!root.goBack()) root.selectCategory(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace && !root.filterText) {
            if (!root.goBack()) root.cancel()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            if (root.activeMenu !== "root" || root.filterText) root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            if (root.activeMenu === "root" && !root.filterText) root.previewCategory(false)
            else root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.activeMenu === "root" && !root.filterText) root.activateCategory(false)
            else if (root.dmenuActive && root.mode === "input") root.applyDmenuSelection(root.filterText)
            else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            event.accepted = true
          } else if (event.key === Qt.Key_Right && !root.filterText) {
            if (root.activeMenuIsTopLevel()) root.selectCategory(1)
            else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm
          anchors.centerIn: parent
          width: Math.min(parent.width, Style.space(520))
          height: Math.min(parent.height, Style.space(280))
          opened: root.deleteConfirmOpen
          z: 10
          message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
          confirmText: "Uninstall"
          background: Qt.rgba(0.02, 0.07, 0.14, 0.96)
          foreground: "white"
          scrim: Qt.rgba(0, 0, 0, 0.6)
          selectedBackground: Qt.rgba(0.25, 0.68, 1.0, 0.42)
          selectedText: "white"
          fontFamily: root.fontFamily
          cornerRadius: Style.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }

      readonly property real hdScale: panel.height / 1080.0
      readonly property real uiScale: Math.max(1.0, panel.height / 1080) * 1.38
      readonly property string xmbFontFamily: {
        if (root.xmbFontChoice === "system") return root.fontFamily
        if (root.xmbFontChoice === "rounded" && ps3FontRounded.status === FontLoader.Ready) return ps3FontRounded.name
        if (root.xmbFontChoice === "pop" && ps3FontPop.status === FontLoader.Ready) return ps3FontPop.name
        return ps3FontRegular.status === FontLoader.Ready ? ps3FontRegular.name : root.fontFamily
      }
      readonly property bool inSubmenu: !root.dmenuActive && !root.filterText && root.navStack.length > 0
      readonly property var submenuParentItem: inSubmenu ? root.item(root.activeMenu) : null
      readonly property var submenuSnapshot: (inSubmenu && root.submenuSnapshotStack.length > 0)
        ? root.submenuSnapshotStack[root.submenuSnapshotStack.length - 1]
        : null
      // Single continuous firmware-verified submenu collapse factor (xmb_plugin.prx .rodata: 240 ms):
      // 0 = full Level-1 XMB, 1 = settled Level-2 (cat shifts -257px/-10px, parent -> 316,
      // siblings -> 455 around focal Y with ◀ chevron, children slide in from +250px right).
      property real subT: inSubmenu ? 1.0 : 0.0
      Behavior on subT { NumberAnimation { duration: 240; easing.type: Easing.OutQuart } }
      // Arbitrary-depth (L2 <-> L3 <-> L4) transition driver mirroring L1 <-> L2 choreography
      // while keeping the top-left category icon parked at subT = 1.
      property int lastNavDepth: 0
      property int deepDir: 0       // +1 = diving deeper (L2->L3), -1 = backing out (L3->L2), 0 = idle
      property real deepT: 1.0
      NumberAnimation {
        id: deepTAnim
        target: card
        property: "deepT"
        from: 0.0
        to: 1.0
        duration: 240
        easing.type: Easing.OutQuart
        onRunningChanged: if (!running) card.deepDir = 0
      }
      // Sony PAF 2-beat label stagger (xmb_plugin.prx 0x18060): 100 ms pause while outgoing labels
      // clear fast (~110 ms) and icons glide ~65% home, then 200 ms OutCubic fade-in for incoming labels.
      property real subLabelReveal: 1.0
      SequentialAnimation {
        id: subLabelRevealAnim
        PauseAnimation { duration: 100 }
        NumberAnimation { target: card; property: "subLabelReveal"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
      }
      Connections {
        target: root
        function onNavStackChanged() {
          var nextDepth = root.navStack.length
          var prevDepth = card.lastNavDepth
          card.lastNavDepth = nextDepth
          if (nextDepth === prevDepth) return
          if (prevDepth > 0 && nextDepth > 0) {
            deepTAnim.stop()
            card.deepDir = (nextDepth > prevDepth) ? 1 : -1
            card.deepT = 0.0
            deepTAnim.restart()
          } else {
            deepTAnim.stop()
            card.deepDir = 0
            card.deepT = 1.0
          }
          subLabelRevealAnim.stop()
          card.subLabelReveal = 0.0
          subLabelRevealAnim.restart()
        }
      }
      readonly property real submenuParentX: categoryAnchorCenterX - Math.round(252 * hdScale)
      readonly property real submenuSibX: categoryAnchorCenterX - Math.round(113 * hdScale)
      readonly property real submenuFocalY: categoryList.baseTopMargin + categoryList.height + Math.round(72 * hdScale)
      // Sony PAF PhText pulsing glow (vsh.elf 0x38cf50): sinusoidal 1.8s breathe (0.35 <-> 0.95).
      property real phTextGlowAlpha: 0.35
      SequentialAnimation on phTextGlowAlpha {
        running: panel.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0.35; to: 0.95; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.95; to: 0.35; duration: 900; easing.type: Easing.InOutSine }
      }

      // Authentic PS3 XMB idle behavior: after ~1.6s without moving, smoothly fade out
      // unselected vertical row labels, leaving icons + the focused item's text.
      property bool navIdle: false
      function pokeNavIdle() {
        navIdle = false
        if (panel.visible && !root.dmenuActive && !root.filterText) xmbIdleTimer.restart()
        else xmbIdleTimer.stop()
      }
      Timer {
        id: xmbIdleTimer
        interval: 1600
        repeat: false
        onTriggered: card.navIdle = true
      }
      Connections {
        target: root
        function onSelectedIndexChanged() { card.pokeNavIdle() }
        function onCategoryIndexChanged() { card.pokeNavIdle() }
        function onActiveMenuChanged() { card.pokeNavIdle() }
        function onFilterTextChanged() { card.pokeNavIdle() }
      }
      Connections {
        target: panel
        function onVisibleChanged() { card.pokeNavIdle() }
      }

      Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Math.round(74 * card.hdScale)
        visible: !!(root.filterText && root.mode !== "input")
        text: "Search: " + root.filterText
        color: "white"
        opacity: 0.85
        font.family: card.xmbFontFamily
        font.pixelSize: Math.max(14, Style.font.body, Math.round(14 * card.uiScale))
        font.weight: Font.Light
        font.letterSpacing: 1.5
      }

      // Authentic PS3 XMB top-right clock indicator (xmb_plugin_normal.rco + layout_grid_table_1080.txt):
      // 560x59 px visible hairline-to-hairline @ 1080p, flush right, 74 px from top;
      // clock + dial right-aligned to the 90% TV overscan safe zone (~115 px from right edge).
      Item {
        id: xmbClockBox
        anchors.right: parent.right
        anchors.rightMargin: -card.anchors.rightMargin
        anchors.top: parent.top
        anchors.topMargin: Math.round(74 * card.hdScale)
        visible: !(root.filterText && root.mode !== "input")
        width: Math.round(592 * card.hdScale)
        height: Math.round(59 * card.hdScale)

        // Optional user-supplied 24x24 9-slice tex_indi_bg, with pure-QML frosted-glass fallback.
        BorderImage {
          id: clockBgImage
          width: 592
          height: 59
          transformOrigin: Item.TopLeft
          scale: card.hdScale
          source: root.modernXmbAssetsDir ? ("file://" + root.modernXmbAssetsDir + "/ui/tex_indi_bg.png") : ""
          visible: status === BorderImage.Ready
          border { left: 8; top: 8; right: 0; bottom: 8 }
          horizontalTileMode: BorderImage.Stretch
          verticalTileMode: BorderImage.Stretch
          smooth: true
        }

        Rectangle {
          anchors.fill: parent
          anchors.rightMargin: -Math.round(8 * card.hdScale)
          visible: clockBgImage.status !== BorderImage.Ready
          radius: Math.round(6 * card.hdScale)
          color: Qt.rgba(0, 0, 0, 0.08)
          border.width: Math.max(1, Math.round(1 * card.hdScale))
          border.color: Qt.rgba(1, 1, 1, 0.35)
        }

        property date now: new Date()
        Timer {
          interval: 15000
          running: panel.visible
          repeat: true
          triggeredOnStart: true
          onTriggered: xmbClockBox.now = new Date()
        }

        // Right-aligned to Sony's 90% TV safe-zone margin (96 px + 19 px = 115 px @ 1080p).
        Row {
          anchors.right: parent.right
          anchors.rightMargin: Math.round(115 * card.hdScale)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Math.round(12 * card.hdScale)

          // Exact clock shadow from xmb_plugin_normal.rco @ 0x1130: offset (+4, +5) px, alpha 0.25.
          Text {
            id: clockText
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(xmbClockBox.now, root.xmbClock24h ? "M/d H:mm" : "M/d h:mm AP")
            color: "white"
            font.family: card.xmbFontFamily
            font.pixelSize: Math.round(26 * card.hdScale)
            layer.enabled: true
            layer.effect: MultiEffect {
              autoPaddingEnabled: true
              shadowEnabled: true
              shadowColor: Qt.rgba(0, 0, 0, 0.25)
              shadowBlur: 0.25
              shadowHorizontalOffset: Math.round(4 * card.hdScale)
              shadowVerticalOffset: Math.round(5 * card.hdScale)
            }
          }

          Canvas {
            id: analogDial
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(32 * card.hdScale)
            height: Math.round(32 * card.hdScale)
            antialiasing: true
            property date timeValue: xmbClockBox.now
            onTimeValueChanged: requestPaint()
            onWidthChanged: requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              var cx = width / 2
              var cy = height / 2
              var r = width * 0.40
              var ringW = Math.max(1.8, width * 0.105)
              var handW = Math.max(1.6, width * 0.09)

              ctx.save()
              ctx.shadowColor = "rgba(0, 0, 0, 0.45)"
              ctx.shadowBlur = Math.max(2, width * 0.08)
              ctx.shadowOffsetX = Math.max(1, width * 0.04)
              ctx.shadowOffsetY = Math.max(1, width * 0.04)

              ctx.strokeStyle = "rgba(255, 255, 255, 0.96)"
              ctx.lineWidth = ringW
              ctx.beginPath()
              ctx.arc(cx, cy, r, 0, Math.PI * 2)
              ctx.stroke()

              var mins = timeValue.getMinutes()
              var hrs = (timeValue.getHours() % 12) + mins / 60.0
              var hourAngle = (hrs / 12.0) * Math.PI * 2 - Math.PI / 2
              var minAngle = (mins / 60.0) * Math.PI * 2 - Math.PI / 2

              ctx.lineWidth = handW
              ctx.lineCap = "round"
              ctx.beginPath()
              ctx.moveTo(cx, cy)
              ctx.lineTo(cx + Math.cos(hourAngle) * r * 0.52, cy + Math.sin(hourAngle) * r * 0.52)
              ctx.stroke()

              ctx.beginPath()
              ctx.moveTo(cx, cy)
              ctx.lineTo(cx + Math.cos(minAngle) * r * 0.74, cy + Math.sin(minAngle) * r * 0.74)
              ctx.stroke()
              ctx.restore()
            }
          }
        }
      }

      Item {
        id: categoryList
        readonly property real baseTopMargin: Math.round(238 * card.hdScale)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: baseTopMargin - Math.round(10 * card.hdScale * card.subT)
        height: Math.round(134 * card.hdScale)
        clip: false
        visible: !root.dmenuActive
        readonly property real delegateWidth: Math.round(170 * card.hdScale)
        readonly property real categoryStep: Math.round(192 * card.hdScale)
        // Exact PS3 1080p column axis (~568 px from screen left = 29.6% of 1920).
        readonly property real selectedCenterX: Math.max(
          width * 0.22,
          Math.round(568 * card.hdScale) - card.anchors.leftMargin
        )
        readonly property real catSubShiftX: -Math.round(257 * card.hdScale) * card.subT

        Repeater {
          model: categoryModel

          delegate: Item {
            id: category
            required property int index
            required property string itemId
            required property string kind
            required property string icon
            required property string iconFont
            required property string label
            required property string target
            required property string action
            readonly property int distance: Math.abs(index - root.categoryIndex)
            readonly property bool selected: distance === 0
            width: categoryList.delegateWidth
            height: categoryList.height
            // Horizontal rail step animates smoothly; submenu shift rides directly on subT.
            property real railX: categoryList.selectedCenterX + (index - root.categoryIndex) * categoryList.categoryStep - width / 2
            Behavior on railX { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
            x: railX + categoryList.catSubShiftX
            z: selected ? 2 : 1
            property real focusScale: selected ? 1.45 : 1.0
            Behavior on focusScale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
            scale: focusScale * (1.0 + (0.833 - 1.0) * card.subT)
            opacity: (selected ? 1.0 : 0.55) * (selected ? (1.0 - 0.40 * card.subT) : (1.0 - card.subT))
            visible: opacity > 0.01
              && x + width > -categoryList.categoryStep
              && x < categoryList.width + categoryList.categoryStep

            Text {
              id: categoryIcon
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              text: category.icon
              color: Qt.rgba(1, 1, 1, category.selected ? 0.90 : 0.72)
              font.family: category.iconFont.length ? category.iconFont : card.xmbFontFamily
              font.pixelSize: Math.round(64 * card.hdScale)
              style: Text.Raised
              styleColor: Qt.rgba(0, 0, 0, 0.45)
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.categoryIndex = category.index
                root.activateCategory(true)
              }
            }
          }
        }

        // Active category label rides directly with catSubShiftX (zero sideways drift when switching categories).
        Item {
          x: categoryList.selectedCenterX + categoryList.catSubShiftX
          y: Math.round(92 * card.hdScale) - Math.round(8 * card.hdScale * card.subT)
          width: 0
          height: 0

          Text {
            id: activeCategoryLabel
            readonly property var curCat: (root.categoryIndex >= 0 && root.categoryIndex < categoryModel.count)
              ? categoryModel.get(root.categoryIndex)
              : null
            anchors.horizontalCenter: parent.horizontalCenter
            text: curCat ? curCat.label : ""
            color: "white"
            opacity: 0.90 * (1.0 - 0.55 * card.subT)
            font.family: card.xmbFontFamily
            font.pixelSize: Math.round(23 * card.hdScale * (1.0 - 0.14 * card.subT))
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.25)
          }
        }
      }

      // A picker takes over the category band: its prompt sits where the
      // selected category would, and its options run through the same
      // vertical carousel as a submenu.
      Column {
        visible: root.dmenuActive
        x: Math.max(0, card.categoryAnchorCenterX - Math.round(27 * card.uiScale))
        width: Math.min(root.dmenuActive
          ? Math.max(420, Style.space(root.dmenuWidth), panel.width * 0.5)
          : Math.max(420, panel.width * 0.34), parent.width - x - (root.dmenuActive ? 32 : 0))
        anchors.verticalCenter: categoryList.verticalCenter
        spacing: Math.round(10 * card.uiScale)

        Text {
          width: parent.width
          text: root.dmenuPrompt
          color: "white"
          font.family: root.fontFamily
          font.pixelSize: Math.max(26, panel.height * 0.032)
          font.weight: Font.Light
          elide: Text.ElideRight
          style: Text.Raised
          styleColor: Qt.rgba(0, 0, 0, 0.55)
        }

        Text {
          width: parent.width
          visible: root.mode === "input"
          text: root.filterText + "▏"
          color: "white"
          font.family: root.fontFamily
          font.pixelSize: Math.round(23 * card.uiScale)
          font.weight: Font.DemiBold
          elide: Text.ElideLeft
        }

        Text {
          width: parent.width
          text: root.mode === "input"
            ? "Enter  confirm      Esc  cancel"
            : "Enter  select      Esc  cancel      Type to filter"
          color: Qt.rgba(1, 1, 1, 0.5)
          font.family: root.fontFamily
          font.pixelSize: Math.round(12 * card.uiScale)
          font.letterSpacing: 1
        }
      }

      // Firmware-verified PS3 Level-2+ parent collapse layer (works seamlessly at L2, L3, L4...;
      // on exit, the real returning xmbRow delegates glide right with zero handoff).
      Item {
        id: submenuBreadcrumbLayer
        anchors.fill: parent
        visible: card.subT > 0.001
        readonly property real collapseT: (card.deepDir === 1) ? card.deepT : card.subT
        readonly property real layerFade: (card.deepDir === -1) ? card.deepT : 1.0
        opacity: layerFade
        readonly property real focalCenterY: card.submenuFocalY + Math.round(66 * card.hdScale)
        readonly property real l1RowStep: Math.round(80 * card.hdScale)
        readonly property real l1SelectedH: Math.round(132 * card.hdScale)
        readonly property real l1RowH: Math.round(72 * card.hdScale)

        Repeater {
          model: (card.inSubmenu && card.submenuSnapshot) ? card.submenuSnapshot.rows : []

          delegate: Item {
            required property var modelData
            required property int index
            readonly property int selIdx: card.submenuSnapshot ? card.submenuSnapshot.selectedIndex : 0
            readonly property int delta: index - selIdx
            readonly property int dist: Math.abs(delta)
            readonly property bool isParentSel: delta === 0
            readonly property real dstX: isParentSel ? card.submenuParentX : card.submenuSibX
            readonly property real curX: card.categoryAnchorCenterX + (dstX - card.categoryAnchorCenterX) * submenuBreadcrumbLayer.collapseT
            // Morph Y continuously from previous level's carousel slot -> collapsed 80px pitch around focalCenterY
            readonly property real srcY: delta < 0
              ? (card.deepDir === 1
                ? (card.submenuFocalY - Math.round(12 * card.hdScale) + delta * submenuBreadcrumbLayer.l1RowStep + submenuBreadcrumbLayer.l1RowH * 0.5)
                : (categoryList.baseTopMargin - Math.round(44 * card.hdScale) + delta * submenuBreadcrumbLayer.l1RowStep + submenuBreadcrumbLayer.l1RowH * 0.5))
              : (delta === 0
                ? submenuBreadcrumbLayer.focalCenterY
                : (card.submenuFocalY + submenuBreadcrumbLayer.l1SelectedH + Math.round((card.deepDir === 1 ? 18 : 42) * card.hdScale) + (delta - 1) * submenuBreadcrumbLayer.l1RowStep + submenuBreadcrumbLayer.l1RowH * 0.5))
            readonly property real dstY: submenuBreadcrumbLayer.focalCenterY + delta * Math.round(80 * card.hdScale)
            readonly property real curY: srcY + (dstY - srcY) * submenuBreadcrumbLayer.collapseT
            readonly property real fullA: isParentSel ? 1.0 : Math.max(0.0, 0.78 - dist * 0.12)
            readonly property real setA: isParentSel ? 0.92 : Math.max(0.12, 0.42 - (dist - 1) * 0.05)
            visible: dist <= 5
            width: Math.round(120 * card.hdScale)
            height: Math.round(120 * card.hdScale)
            x: curX - width / 2
            y: curY - height / 2
            opacity: fullA + (setA - fullA) * submenuBreadcrumbLayer.collapseT

            Image {
              visible: modelData.kind === "app"
              anchors.centerIn: parent
              width: Math.round((isParentSel ? (116 + (64 - 116) * submenuBreadcrumbLayer.collapseT) : (56 + (50 - 56) * submenuBreadcrumbLayer.collapseT)) * card.hdScale)
              height: width
              fillMode: Image.PreserveAspectFit
              sourceSize.width: Math.round(116 * card.hdScale * Screen.devicePixelRatio)
              sourceSize.height: Math.round(116 * card.hdScale * Screen.devicePixelRatio)
              source: visible && root.appLibrary ? root.appLibrary.iconSource(modelData.appIcon) : ""
              asynchronous: true
            }

            Text {
              visible: modelData.kind !== "app"
              anchors.centerIn: parent
              text: modelData.icon || "•"
              color: Qt.rgba(1, 1, 1, isParentSel ? 0.94 : 0.80)
              font.family: (modelData.iconFont && modelData.iconFont.length) ? modelData.iconFont : card.xmbFontFamily
              font.pixelSize: Math.round((isParentSel ? (108 + (62 - 108) * submenuBreadcrumbLayer.collapseT) : (54 + (48 - 54) * submenuBreadcrumbLayer.collapseT)) * card.hdScale)
              style: Text.Raised
              styleColor: Qt.rgba(0, 0, 0, 0.35)
            }

            // Outgoing parent title + subtitle clear fast (~110 ms) as parent icon slides left,
            // so child text never collides mid-flight (xmb_plugin.prx 2-beat choreography).
            Column {
              readonly property real outAlpha: Math.max(0.0, 1.0 - submenuBreadcrumbLayer.collapseT * 2.2)
              visible: outAlpha > 0.01 && (modelData.label || "").length > 0
              x: parent.width * 0.5 + Math.round((isParentSel ? 90 : 54) * card.hdScale)
              width: Math.round(700 * card.hdScale)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Math.round(2 * card.hdScale)
              opacity: outAlpha * (isParentSel ? 1.0 : 0.85)

              Text {
                width: parent.width
                text: modelData.label || ""
                color: "white"
                font.family: card.xmbFontFamily
                font.pixelSize: Math.round((isParentSel ? 34 : 24) * card.hdScale)
                style: isParentSel ? Text.Normal : Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.25)
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: isParentSel && (modelData.subtitle || "").length > 0
                text: modelData.subtitle || ""
                color: Qt.rgba(1, 1, 1, 0.88)
                font.family: card.xmbFontFamily
                font.pixelSize: Math.round(21 * card.hdScale)
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.25)
                elide: Text.ElideRight
              }
            }

            MouseArea {
              enabled: isParentSel
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goBack()
            }
          }
        }

        // Back-chevron breadcrumb: crisp left-pointing ◀ in the vacated parent slot at submenuSibX
        Text {
          x: card.submenuSibX - width / 2
          y: submenuBreadcrumbLayer.focalCenterY - height / 2
          text: "◀"
          color: Qt.rgba(0.84, 0.84, 0.86, 0.95)
          opacity: card.subT
          font.family: card.xmbFontFamily
          font.pixelSize: Math.round(28 * card.hdScale)
          style: Text.Raised
          styleColor: Qt.rgba(0, 0, 0, 0.45)

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Math.round(14 * card.hdScale)
            cursorShape: Qt.PointingHandCursor
            onClicked: root.goBack()
          }
        }
      }

      Column {
        id: xmbListColumn
        anchors.left: parent.left
        // Level-2 children settle at the exact main column axis (568), sliding in from +250 px right!
        anchors.leftMargin: Math.max(0, card.categoryAnchorCenterX - Math.round(72 * card.hdScale))
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.min(root.dmenuActive
          ? Math.max(420, Style.space(root.dmenuWidth), panel.width * 0.5)
          : Math.max(420, panel.width * 0.34), parent.width - x - (root.dmenuActive ? 32 : 0))
        spacing: 0
        visible: root.activeMenu !== "root" || root.filterText || root.dmenuActive

        // Child column slides in from +250 px right on L1->L2 or L2->L3+ drilldown (not on L3->L2 return).
        transform: Translate {
          x: (card.inSubmenu && card.deepDir !== -1)
            ? Math.round(250 * card.hdScale * (1.0 - (card.deepDir === 1 ? card.deepT : card.subT)))
            : 0
        }
        opacity: (card.inSubmenu && card.deepDir !== -1) ? card.subLabelReveal : 1.0

        Text {
          width: 0
          height: 0
          visible: false
          text: root.filterText || (root.dmenuActive ? root.dmenuPrompt : ((root.item(root.activeMenu) && (root.item(root.activeMenu).title || root.item(root.activeMenu).label)) || "Menu"))
          color: "white"
          opacity: 0.94
          font.family: root.fontFamily
          font.pixelSize: Math.max(22, Style.font.title)
          font.weight: Font.Light
          elide: Text.ElideRight
        }

        Rectangle { width: 0; height: 0; visible: false }

        Item {
          id: xmbResultList
          width: parent.width
          height: parent.height
          clip: false

          Repeater {
            model: displayModel

            delegate: Item {
              id: xmbRow
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string iconFont
              required property string appIcon
              required property string appId
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount

              readonly property bool selected: root.cursorActive && index === root.selectedIndex
              readonly property int rowDist: Math.abs(index - root.selectedIndex)
              // Anchor to categoryList.baseTopMargin (constant) so Behavior on y never lags behind subT!
              readonly property real selectedY: card.submenuFocalY
              // Keybinding labels contain a padded shortcut, an arrow and its
              // description. Split only their presentation: callers still receive
              // the original label verbatim when the row is selected.
              readonly property int descriptionSeparator: root.dmenuActive ? label.indexOf(" → ") : -1
              readonly property string displayLabel: descriptionSeparator >= 0
                ? label.slice(0, descriptionSeparator).trim() : label
              readonly property string displayDetail: descriptionSeparator >= 0
                ? label.slice(descriptionSeparator + 3).trim() + (detail ? " — " + detail : "") : detail
              readonly property string subtitleText: displayDetail.length > 0
                ? displayDetail
                : (childCount > 0 ? (childCount + (childCount === 1 ? " Item" : " Items")) : "")
              readonly property real selectedHeight: root.dmenuActive ? Math.round(176 * card.hdScale) : Math.round(132 * card.hdScale)
              readonly property real rowStep: root.dmenuActive ? Math.round(104 * card.hdScale) : Math.round(80 * card.hdScale)
              readonly property real baseOpacity: selected ? 1.0 : Math.max(0.0, 0.78 - rowDist * 0.12)
              readonly property real rowCenterY: y + height * 0.5
              readonly property real barFade: (!root.dmenuActive && !card.inSubmenu && rowCenterY > categoryList.baseTopMargin && rowCenterY < categoryList.baseTopMargin + categoryList.height) ? 0.15 : 1.0
              readonly property real bottomFade: Math.min(1.0, Math.max(0.0, (xmbResultList.height - (y + height)) / Math.round(90 * card.hdScale)))
              width: xmbResultList.width
              height: selected ? selectedHeight : (root.dmenuActive ? Math.round(92 * card.hdScale) : Math.round(72 * card.hdScale))
              y: index < root.selectedIndex
                ? (card.inSubmenu
                  ? (selectedY - Math.round(12 * card.hdScale) - (root.selectedIndex - index) * rowStep)
                  : (categoryList.baseTopMargin - Math.round(44 * card.hdScale) - (root.selectedIndex - index) * rowStep))
                : (index === root.selectedIndex
                  ? selectedY
                  : selectedY + selectedHeight + Math.round(card.inSubmenu ? 18 : 42) * card.hdScale + (index - root.selectedIndex - 1) * rowStep)
              // On any back-out (L2->L1 via subT 1->0, or L3+->L2+ via deepDir === -1), each real
              // returning xmbRow glides directly from its collapsed breadcrumb/sibling slot back to (0, 0).
              readonly property real exitT: (card.deepDir === -1)
                ? (1.0 - card.deepT)
                : ((!card.inSubmenu && !root.dmenuActive && !root.filterText) ? card.subT : 0.0)
              readonly property real collapsedCenterY: (card.submenuFocalY + Math.round(66 * card.hdScale)) + (index - root.selectedIndex) * Math.round(80 * card.hdScale)
              readonly property real exitOffsetX: (selected ? -Math.round(252 * card.hdScale) : -Math.round(113 * card.hdScale)) * exitT
              readonly property real exitOffsetY: (collapsedCenterY - (y + height * 0.5)) * exitT
              readonly property real exitSetAlpha: selected ? 0.92 : Math.max(0.12, 0.42 - (rowDist - 1) * 0.05)
              transform: Translate {
                x: xmbRow.exitOffsetX
                y: xmbRow.exitOffsetY
              }
              visible: (y + exitOffsetY) + height > 0 && (y + exitOffsetY) < xmbResultList.height
              property real navOpacity: baseOpacity * barFade * bottomFade
              Behavior on navOpacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
              opacity: navOpacity * (1.0 - exitT) + exitSetAlpha * exitT
              Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }

              Image {
                id: xmbAppImage
                visible: xmbRow.kind === "app"
                width: xmbRow.selected ? Math.round(116 * card.hdScale) : Math.round(56 * card.hdScale)
                height: width
                scale: xmbRow.exitT > 0 ? (xmbRow.selected ? (1.0 + (64.0 / 116.0 - 1.0) * xmbRow.exitT) : (1.0 + (50.0 / 56.0 - 1.0) * xmbRow.exitT)) : 1.0
                anchors.horizontalCenter: xmbRowIcon.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: visible && root.appLibrary ? root.appLibrary.iconSource(xmbRow.appIcon) : ""
                asynchronous: true
              }

              Text {
                id: xmbRowIcon
                visible: xmbRow.kind !== "app"
                width: Math.round(144 * card.hdScale)
                height: parent.height
                anchors.left: parent.left
                scale: xmbRow.exitT > 0 ? (xmbRow.selected ? (1.0 + (62.0 / 108.0 - 1.0) * xmbRow.exitT) : (1.0 + (48.0 / 54.0 - 1.0) * xmbRow.exitT)) : 1.0
                text: xmbRow.icon || "•"
                color: Qt.rgba(1, 1, 1, xmbRow.selected ? 0.94 : 0.80)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: xmbRow.iconFont.length ? xmbRow.iconFont : card.xmbFontFamily
                font.pixelSize: xmbRow.selected ? Math.round(108 * card.hdScale) : Math.round(54 * card.hdScale)
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.35)
                Behavior on font.pixelSize { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
              }

              Column {
                anchors.left: parent.left
                anchors.leftMargin: xmbRow.selected ? Math.round(162 * card.hdScale) : Math.round(126 * card.hdScale)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(2 * card.hdScale)
                property real idleOpacity: (xmbRow.selected || !card.navIdle || root.dmenuActive || root.filterText.length > 0) ? 1.0 : 0.0
                Behavior on idleOpacity { NumberAnimation { duration: card.navIdle ? 450 : 120; easing.type: Easing.OutCubic } }
                opacity: idleOpacity * ((!card.inSubmenu || card.deepDir === -1) ? card.subLabelReveal : 1.0)

                Item {
                  width: parent.width
                  height: xmbRowLabel.implicitHeight

                  // Sony PAF PhText "Text(shadow)" glow (vsh.elf 0x38cf50):
                  // Centered (0,0) behind selected text, tinted pure white, pulsing 0.35 <-> 0.95.
                  MultiEffect {
                    source: xmbRowLabel
                    anchors.fill: xmbRowLabel
                    visible: xmbRow.selected
                    autoPaddingEnabled: true
                    blurEnabled: true
                    blur: 0.72
                    blurMax: 24
                    colorization: 1.0
                    colorizationColor: "#ffffff"
                    opacity: card.phTextGlowAlpha
                  }

                  Text {
                    id: xmbRowLabel
                    width: parent.width
                    text: xmbRow.displayLabel
                    color: "white"
                    font.family: card.xmbFontFamily
                    font.pixelSize: xmbRow.selected ? Math.round(34 * card.hdScale) : Math.round(24 * card.hdScale)
                    style: xmbRow.selected ? Text.Normal : Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.25)
                    elide: Text.ElideRight
                    Behavior on font.pixelSize { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
                  }
                }

                Text {
                  width: parent.width
                  visible: (xmbRow.selected && xmbRow.subtitleText.length > 0) || ((root.filterText || root.dmenuActive) && xmbRow.displayDetail.length > 0)
                  text: (root.filterText || root.dmenuActive) && xmbRow.displayDetail.length > 0 ? xmbRow.displayDetail : xmbRow.subtitleText
                  color: xmbRow.selected ? Qt.rgba(1, 1, 1, 0.88) : Qt.rgba(1, 1, 1, 0.62)
                  font.family: card.xmbFontFamily
                  font.pixelSize: root.dmenuActive ? (xmbRow.selected ? Math.round(22 * card.hdScale) : Math.round(18 * card.hdScale)) : Math.round(21 * card.hdScale)
                  style: Text.Raised
                  styleColor: Qt.rgba(0, 0, 0, 0.25)
                  wrapMode: root.dmenuActive && xmbRow.selected ? Text.WordWrap : Text.NoWrap
                  maximumLineCount: root.dmenuActive && xmbRow.selected ? 3 : 1
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.selectedIndex = xmbRow.index; root.activateIndex(xmbRow.index, true) }
              }
            }
          }

          Text {
            x: Math.round(48 * card.uiScale)
            y: categoryList.y + categoryList.height + Math.round(46 * card.uiScale)
            visible: root.dmenuActive && root.mode !== "input" && displayModel.count === 0
            text: root.filterText ? "No matches" : "Nothing here yet"
            color: "white"
            opacity: 0.62
            font.family: root.fontFamily
            font.pixelSize: Math.round(20 * card.uiScale)
          }
        }
      }

    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property int selectedIndex: 0
  property int categoryIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var submenuSnapshotStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  // Qt can turn manifest.kinds into a sequence while loading third-party
  // menus, causing the host to omit its scoped app library. Reuse the host's
  // engine so filtering, icons and launch feedback stay consistent.
  readonly property var appLibrary: root.shell && root.shell.appLibrary
    ? root.shell.appLibrary : fallbackAppLibrary.item
  onAppLibraryChanged: {
    if (root.appLibrary && root.providersLoaded["apps"]) root.mergeAppRows()
  }

  Loader {
    id: fallbackAppLibrary
    active: !!root.shell && !root.shell.appLibrary
    sourceComponent: Component {
      AppLibrary { omarchyPath: root.omarchyPath }
    }
  }
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  onOpenedChanged: if (!opened) { deleteConfirmOpen = false; deleteTarget = null }
  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int baseRowHeight: Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Style.spacing.xs
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(300)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight, panel.height - Style.gapsOut * 2)

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.7))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  function injectXmbSettingsMenu(mergedMenu) {
    var items = mergedMenu.items
    var order = mergedMenu.itemOrder
    if (!items["appearance"]) return

    function addEntry(id, entry) {
      entry.id = id
      if (!items[id]) order.push(id)
      items[id] = entry
    }

    var qrcPresets = root.discoveredQrcPresets || []
    var curQrcLabel = root.effectiveNativeBackend ? "Custom" : "QML Fallback"
    for (var qi = 0; qi < qrcPresets.length; qi++) {
      if (qrcPresets[qi].path === root.nativeBackendQrc) { curQrcLabel = qrcPresets[qi].label; break }
    }

    var months = [
      { val: "auto", label: "Auto (System Month)" },
      { val: "1", label: "January" }, { val: "2", label: "February" }, { val: "3", label: "March" },
      { val: "4", label: "April" }, { val: "5", label: "May" }, { val: "6", label: "June" },
      { val: "7", label: "July" }, { val: "8", label: "August" }, { val: "9", label: "September" },
      { val: "10", label: "October" }, { val: "11", label: "November" }, { val: "12", label: "December" }
    ]
    var curMonthLabel = "Auto"
    for (var mi = 0; mi < months.length; mi++) {
      if (months[mi].val === root.xmbMonth) { curMonthLabel = months[mi].label; break }
    }

    var times = [
      { val: "auto", label: "Auto (System Clock)" },
      { val: "dawn", label: "Dawn" },
      { val: "noon", label: "Noon" },
      { val: "dusk", label: "Dusk" },
      { val: "night", label: "Night" }
    ]
    var curTimeLabel = root.xmbTime
    for (var ti = 0; ti < times.length; ti++) {
      if (times[ti].val === root.xmbTime) { curTimeLabel = times[ti].label; break }
    }

    var opacities = [0.85, 0.92, 0.96, 0.99, 1.0]
    var curOpacityLabel = Math.round(root.nativeBackendOpacity * 100) + "%"

    var fonts = [
      { val: "rodin", label: "PS3 Rodin (Default)" },
      { val: "rounded", label: "PS3 Rounded" },
      { val: "pop", label: "PS3 Pop" },
      { val: "system", label: "Omarchy System Font" }
    ]
    var curFontLabel = "PS3 Rodin"
    for (var fi = 0; fi < fonts.length; fi++) {
      if (fonts[fi].val === root.xmbFontChoice) { curFontLabel = fonts[fi].label; break }
    }

    addEntry("appearance.xmb", { parent: "appearance", kind: "menu", icon: "󰔎", label: "XMB Menu", detail: curQrcLabel })

    addEntry("appearance.xmb.qrc", { parent: "appearance.xmb", kind: "menu", icon: "󰸉", label: "Theme / Wave", detail: curQrcLabel })
    for (var q = 0; q < qrcPresets.length; q++) {
      var qp = qrcPresets[q]
      var isJson = qp.path && qp.path.slice(-5) === ".json"
      var isQrc = qp.path && qp.path.slice(-4) === ".qrc"
      var themeIcon = isJson ? "󰘦" : (isQrc ? "󰏗" : "󰸉")
      var themeDetail = isJson ? "JSON Theme" : (isQrc ? "QRC Archive" : "Procedural")
      addEntry("appearance.xmb.qrc." + qp.id, {
        parent: "appearance.xmb.qrc", kind: "action", icon: themeIcon,
        label: (qp.path === root.nativeBackendQrc ? "✓ " : "") + qp.label,
        detail: themeDetail,
        action: "xmb:qrc:" + qp.path
      })
    }

    addEntry("appearance.xmb.month", { parent: "appearance.xmb", kind: "menu", icon: "󰃭", label: "Month / Color", detail: curMonthLabel })
    for (var m = 0; m < months.length; m++) {
      var mo = months[m]
      addEntry("appearance.xmb.month." + mo.val, {
        parent: "appearance.xmb.month", kind: "action", icon: "󰃭",
        label: (mo.val === root.xmbMonth ? "✓ " : "") + mo.label,
        action: "xmb:month:" + mo.val
      })
    }

    addEntry("appearance.xmb.time", { parent: "appearance.xmb", kind: "menu", icon: "󰖨", label: "Time of Day", detail: curTimeLabel })
    for (var t = 0; t < times.length; t++) {
      var tm = times[t]
      addEntry("appearance.xmb.time." + tm.val, {
        parent: "appearance.xmb.time", kind: "action", icon: "󰖨",
        label: (tm.val === root.xmbTime ? "✓ " : "") + tm.label,
        action: "xmb:time:" + tm.val
      })
    }

    addEntry("appearance.xmb.opacity", { parent: "appearance.xmb", kind: "menu", icon: "󰂵", label: "Background Opacity", detail: curOpacityLabel })
    for (var o = 0; o < opacities.length; o++) {
      var ov = opacities[o]
      var pct = Math.round(ov * 100) + "%"
      var isCurOp = Math.abs(ov - root.nativeBackendOpacity) < 0.005
      addEntry("appearance.xmb.opacity." + Math.round(ov * 100), {
        parent: "appearance.xmb.opacity", kind: "action", icon: "󰂵",
        label: (isCurOp ? "✓ " : "") + pct,
        action: "xmb:opacity:" + String(ov)
      })
    }

    addEntry("appearance.xmb.font", { parent: "appearance.xmb", kind: "menu", icon: "󰛖", label: "Font", detail: curFontLabel })
    for (var f = 0; f < fonts.length; f++) {
      var fn = fonts[f]
      addEntry("appearance.xmb.font." + fn.val, {
        parent: "appearance.xmb.font", kind: "action", icon: "󰛖",
        label: (fn.val === root.xmbFontChoice ? "✓ " : "") + fn.label,
        action: "xmb:font:" + fn.val
      })
    }

    addEntry("appearance.xmb.clock", { parent: "appearance.xmb", kind: "menu", icon: "󰥔", label: "Clock Format", detail: root.xmbClock24h ? "24-Hour" : "12-Hour" })
    addEntry("appearance.xmb.clock.12", { parent: "appearance.xmb.clock", kind: "action", icon: "󰥔", label: (!root.xmbClock24h ? "✓ " : "") + "12-Hour (AM/PM)", action: "xmb:clock24h:false" })
    addEntry("appearance.xmb.clock.24", { parent: "appearance.xmb.clock", kind: "action", icon: "󰥔", label: (root.xmbClock24h ? "✓ " : "") + "24-Hour", action: "xmb:clock24h:true" })

    addEntry("appearance.xmb.renderer", { parent: "appearance.xmb", kind: "menu", icon: "󰍹", label: "Renderer", detail: root.effectiveNativeBackend ? "modern-moyou (Vulkan)" : "QML Shader Fallback" })
    addEntry("appearance.xmb.renderer.native", { parent: "appearance.xmb.renderer", kind: "action", icon: "󰍹", label: (root.useNativeBackend ? "✓ " : "") + "modern-moyou (Vulkan)", action: "xmb:renderer:native" })
    addEntry("appearance.xmb.renderer.qml", { parent: "appearance.xmb.renderer", kind: "action", icon: "󰍹", label: (!root.useNativeBackend ? "✓ " : "") + "QML Shader Fallback", action: "xmb:renderer:qml" })
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.injectXmbSettingsMenu(mergedMenu)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rebuildCategories()
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  function rebuildCategories() {
    categoryModel.clear()
    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || entry.parent !== "root") continue
      if (entry.when && root.whenResults[entry.id] === false) continue
      categoryModel.append({
        itemId: entry.id,
        kind: entry.kind,
        icon: entry.icon || "•",
        iconFont: entry.iconFont || "",
        label: entry.label || entry.id,
        target: entry.target || "",
        action: entry.action || ""
      })
    }
    if (categoryModel.count === 0) root.categoryIndex = 0
    else root.categoryIndex = Math.max(0, Math.min(root.categoryIndex, categoryModel.count - 1))
  }

  function selectCategory(delta) {
    if (categoryModel.count === 0) return
    var nextIndex = Math.max(0, Math.min(categoryModel.count - 1, root.categoryIndex + delta))
    if (nextIndex === root.categoryIndex) return
    root.categoryIndex = nextIndex
    root.waveTargetX = Math.max(-0.10, Math.min(0.10, root.waveTargetX + (delta > 0 ? 0.06 : -0.06)))
    root.sendNavWind(delta > 0 ? "right" : "left")
    if (!root.filterText) root.previewCategory(false)
  }

  function activeMenuIsTopLevel() {
    var active = root.item(root.activeMenu)
    return !!active && active.parent === "root"
  }

  function activateCategory(fromPointer) {
    if (root.categoryIndex < 0 || root.categoryIndex >= categoryModel.count) return
    var category = categoryModel.get(root.categoryIndex)
    if (category.kind === "action") root.applySelected(category.itemId, category.action)
    else root.previewCategory(fromPointer)
  }

  function previewCategory(fromPointer) {
    if (root.categoryIndex < 0 || root.categoryIndex >= categoryModel.count) return
    var category = categoryModel.get(root.categoryIndex)
    if (category.kind === "action") {
      root.activeMenu = "root"
      root.navStack = []
      root.submenuSnapshotStack = []
      root.selectedIndex = 0
      root.cursorActive = false
      root.rebuildDisplay()
      return
    }
    root.setActiveMenu(category.target || category.itemId, false, fromPointer)
  }

  function syncCategoryToMenu() {
    var topId = root.activeMenu
    var current = root.item(topId)
    var guard = 0
    while (current && current.parent && current.parent !== "root" && guard < 32) {
      topId = current.parent
      current = root.item(topId)
      guard += 1
    }
    for (var i = 0; i < categoryModel.count; i++) {
      if (categoryModel.get(i).itemId === topId) {
        root.categoryIndex = i
        return
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    if (!root.appLibrary) return

    var rows = root.appLibrary.sortedEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
  }

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var searchRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        searchRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      searchRows.sort(searchSort)
      rows = searchRows
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
  }

  function select(delta) {
    if (displayModel.count === 0) return

    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      // Page Up can move farther than the length of a short list. JavaScript
      // remainder may be negative, so normalize it before using it as an index.
      selectedIndex = ((selectedIndex + delta) % displayModel.count + displayModel.count) % displayModel.count
    }
    root.waveTargetY = Math.max(-0.08, Math.min(0.08, root.waveTargetY + (delta > 0 ? -0.045 : 0.045)))
    root.sendNavWind(delta > 0 ? "down" : "up")
    if (root.activeMenu.indexOf("appearance.xmb.") === 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count) {
      root.previewXmbAction(displayModel.get(root.selectedIndex).action)
    }
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer, initialSelectedIndex) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) {
      var snapRows = []
      for (var s = 0; s < displayModel.count; s++) {
        var r = displayModel.get(s)
        var rawLabel = r.label || ""
        var rawDetail = r.detail || ""
        var subTxt = rawDetail.length > 0
          ? rawDetail
          : (r.childCount > 0 ? (r.childCount + (r.childCount === 1 ? " Item" : " Items")) : "")
        snapRows.push({
          label: rawLabel,
          subtitle: subTxt,
          icon: r.icon || "",
          iconFont: r.iconFont || "",
          kind: r.kind || "",
          appIcon: r.appIcon || ""
        })
      }
      root.submenuSnapshotStack = root.submenuSnapshotStack.concat([{
        rows: snapRows,
        selectedIndex: root.selectedIndex
      }])
      root.navStack = root.navStack.concat([root.activeMenu])
      root.sendNavWind("right")
    }
    root.activeMenu = id
    root.syncCategoryToMenu()
    root.filterText = ""
    root.selectedIndex = (initialSelectedIndex !== undefined && initialSelectedIndex >= 0) ? initialSelectedIndex : 0
    root.cursorActive = true
    root.rebuildDisplay()
    if (root.selectedIndex >= displayModel.count) root.selectedIndex = Math.max(0, displayModel.count - 1)
    if (id.indexOf("appearance.xmb.") === 0 && initialSelectedIndex === undefined) {
      for (var ci = 0; ci < displayModel.count; ci++) {
        if ((displayModel.get(ci).label || "").indexOf("✓ ") === 0) {
          root.selectedIndex = ci
          break
        }
      }
    }
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false
    root.restoreXmbLiveState()

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      var prevSnap = root.submenuSnapshotStack.length > 0
        ? root.submenuSnapshotStack[root.submenuSnapshotStack.length - 1]
        : null
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.submenuSnapshotStack = root.submenuSnapshotStack.slice(0, Math.max(0, root.submenuSnapshotStack.length - 1))
      root.setActiveMenu(previous, false, false, prevSnap ? prevSnap.selectedIndex : 0)
      root.sendNavWind("left")
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(appId, label)
    } else if (row.action && row.action.indexOf("xmb:") === 0) {
      root.applyXmbAction(row.action)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  // A picker summoned by omarchy-menu-select or omarchy-menu-input has no
  // category carousel to drive, so the root-menu bindings would switch
  // categories (or run a category's action) instead of picking an option.
  function handleDmenuKey(event) {
    var key = event.key
    if (key === Qt.Key_Escape) {
      if (root.filterText) root.setFilter("")
      else root.cancel()
    } else if (Util.editsFilter(event, root.filterText)) {
      root.setFilter(Util.editedFilter(event, root.filterText))
    } else if ((key === Qt.Key_Backspace || key === Qt.Key_Left) && !root.filterText) {
      root.cancel()
    } else if (key === Qt.Key_Up) {
      root.select(-1)
    } else if (key === Qt.Key_Down) {
      root.select(1)
    } else if (key === Qt.Key_PageUp) {
      root.select(-6)
    } else if (key === Qt.Key_PageDown) {
      root.select(6)
    } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
    } else if (key === Qt.Key_Right && root.mode !== "input") {
      root.activateIndex(root.selectedIndex)
    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
      root.setFilter(root.filterText + event.text)
    } else {
      return false
    }
    return true
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    submenuSnapshotStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.evaluateGuards()
    opened = true
    if (activeMenu === "root" && categoryModel.count > 0) {
      categoryIndex = 0
      root.previewCategory(false)
    } else {
      root.syncCategoryToMenu()
      rebuildDisplay()
      invalidateVolatileProvider(activeMenu)
      loadProviderForMenu(activeMenu)
    }
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    submenuSnapshotStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }
  ListModel { id: categoryModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      root.rebuildCategories()
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
}
