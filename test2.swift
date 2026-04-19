import Foundation
import LibHangul

let ctx = HangulInputContext(keyboard: "2")
let result = ctx.process("A")
print("Process Result:", result)
print("Commit:", ctx.getCommitString().map { String(format: "%X", $0) })
print("Preedit:", ctx.getPreeditString().map { String(format: "%X", $0) })
