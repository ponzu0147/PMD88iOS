import Foundation

// Z80 CPU フラグ定数
let S_FLAG: UInt8 = 0x80 // サインフラグ
let Z_FLAG: UInt8 = 0x40 // ゼロフラグ
let H_FLAG: UInt8 = 0x10 // ハーフキャリーフラグ
let P_FLAG: UInt8 = 0x04 // パリティ/オーバーフローフラグ
let N_FLAG: UInt8 = 0x02 // 減算フラグ
let C_FLAG: UInt8 = 0x01 // キャリーフラグ 