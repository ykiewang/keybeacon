# Data Model: 006-keymap-viewer

**Date**: 2026-11-26 | **Phase**: 1

## Core Types（BleWidgetCore）

### BehaviorID

```swift
enum BehaviorID: UInt8 {
    case kp          = 0x01
    case mt          = 0x02
    case lt          = 0x03
    case mo          = 0x04
    case to          = 0x05
    case tog         = 0x06
    case sl          = 0x07
    case sk          = 0x08
    case trans       = 0x09
    case none        = 0x0A
    case keyRepeat   = 0x0B
    case gresc       = 0x0C
    case capsWord    = 0x0D
    case kt          = 0x0E
    case td          = 0x10
    case macro       = 0x11
    case modMorph    = 0x12
    case bt          = 0x20
    case out         = 0x21
    case reset       = 0x22
    case bootloader  = 0x23
    case mkp         = 0x30
    case rgb         = 0x40
    case bl          = 0x41
    case extPower    = 0x42
    case softOff     = 0x43
    case studioUnlock = 0x44
    case unknown     = 0xFF
}
```

### KeyEntry

物理键坐标/尺寸/旋转，对应固件 `key_entry` 结构体（10 字节）：

```swift
struct KeyEntry {
    let x:  Int16   // 0.01u，键左上角 x
    let y:  Int16   // 0.01u，键左上角 y
    let w:  UInt8   // 0.1u，宽
    let h:  UInt8   // 0.1u，高
    let r:  Int16   // 0.01°，旋转角
    let rx: Int16   // 0.01u，旋转原点 x
    let ry: Int16   // 0.01u，旋转原点 y
}
```

单位转换：1u = 54pt（`KeymapView` 渲染时使用）。

### BindingEntry

每个 layer 中每个键的 binding，对应固件 `binding_entry` 结构体（5 字节）：

```swift
struct BindingEntry {
    let behaviorID: BehaviorID
    let param1:     UInt16
    let param2:     UInt16
}
```

### KeymapSnapshot

完整的键位图数据（从 `KeymapData` 解析后）：

```swift
struct KeymapSnapshot: Codable {
    let keys:       [KeyEntry]           // 长度 = keyCount
    let layerNames: [String]             // 长度 = layerCount
    let bindings:   [[BindingEntry]]     // [layerIndex][keyIndex]
}
```

### KeymapMeta

从 `KeymapMeta` 特征解析的元信息：

```swift
struct KeymapMeta {
    let crc32:      UInt32
    let layerCount: UInt8
    let keyCount:   UInt16
    let layerNames: [String]
}
```

## 缓存存储格式

**Key 格式**：`"keymapCache_\(peripheralUUID)_\(crc32hex)"`

**Value**：`KeymapSnapshot` 编码为 JSON `Data`，存入 `UserDefaults`。

```swift
// AppSettings 新增属性
func keymapSnapshot(for uuid: UUID, crc32: UInt32) -> KeymapSnapshot?
func setKeymapSnapshot(_ snapshot: KeymapSnapshot, for uuid: UUID, crc32: UInt32)
```

## Binding 渲染逻辑

```
BindingEntry → displayLabel(layerNames:) → (topLabel: String?, mainLabel: String)
```

| BehaviorID | topLabel | mainLabel |
|-----------|---------|----------|
| `.kp` | nil | HID keycode 名（`A`、`LSHIFT`、`F5`…） |
| `.mt` | HID(param1) 小字 | HID(param2) 大字 |
| `.lt` | layerNames[param1] 小字 | HID(param2) 大字 |
| `.mo` | nil | `MO(\(layerNames[param1]))` |
| `.to` | nil | `TO(\(layerNames[param1]))` |
| `.tog` | nil | `TG(\(layerNames[param1]))` |
| `.sl` | nil | `SL(\(layerNames[param1]))` |
| `.sk` | nil | modifier名 + `¹` |
| `.trans` | nil | `▽` |
| `.none` | nil | `✕` |
| `.keyRepeat` | nil | `↺` |
| `.gresc` | nil | `` `/ESC `` |
| `.capsWord` | nil | `CAPS▶` |
| `.kt` | nil | `KT(\(HID(param1)))` |
| `.td` | nil | `TD` |
| `.macro` | nil | `▶M` |
| `.modMorph` | nil | `MM` |
| `.bt` | nil | `BT(\(param1))` |
| `.out` | nil | `USB` / `BLE`（param1=0/1） |
| `.reset` | nil | `RST` |
| `.bootloader` | nil | `BOOT` |
| `.mkp` | nil | `MB\(param1)` |
| `.rgb` | nil | `RGB` |
| `.bl` | nil | `BL` |
| `.extPower` | nil | `PWR` |
| `.softOff` | nil | `OFF` |
| `.studioUnlock` | nil | `STU` |
| `.unknown` | nil | `?` |

## ATT READ_BLOB 协议

`KeymapData`（`AA440AA6`）使用标准 BLE ATT READ_BLOB：

```
app → READ_BLOB(handle, offset=0)
firmware → data[0..ATT_MTU-1]
app → READ_BLOB(handle, offset=ATT_MTU-1)
firmware → data[ATT_MTU-1..2*(ATT_MTU-1)-1]
...
直到 firmware 返回空 payload（offset >= totalLen）
```

`KeymapDataFetcher` 在 BleWidgetCore 实现此循环，拼合完整 Data 后解析。
