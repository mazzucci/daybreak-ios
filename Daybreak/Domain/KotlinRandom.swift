/// Kotlin's `Random(seed: Long)` (the XorWow generator in kotlin.random), bit for bit, so a list shuffled with the
/// same seed comes out in the same order as on Android. On this day uses it to break ties with the date, which keeps
/// the two apps' picks for a day the same.
struct KotlinRandom {
    private var x: Int32
    private var y: Int32
    private var z: Int32
    private var w: Int32
    private var v: Int32
    private var addend: Int32

    init(seed: Int64) {
        let seed1 = Int32(truncatingIfNeeded: seed)
        let seed2 = Int32(truncatingIfNeeded: seed >> 32)
        x = seed1
        y = seed2
        z = 0
        w = 0
        v = ~seed1
        addend = (seed1 << 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) >> 4)
        // As Kotlin does: some trivial seeds give several values with zeroes in the upper bits, so the first 64 go.
        for _ in 0..<64 { _ = nextInt() }
    }

    mutating func nextInt() -> Int32 {
        var t = x
        t ^= Int32(bitPattern: UInt32(bitPattern: t) >> 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t << 1)) ^ v0 ^ (v0 << 4)
        v = t
        addend = addend &+ 362_437
        return t &+ addend
    }

    private mutating func nextBits(_ bitCount: Int32) -> Int32 {
        let r = nextInt()
        // takeUpperBits: the top bitCount bits, or 0 for a count of 0.
        return Int32(bitPattern: UInt32(bitPattern: r) >> UInt32(32 - bitCount)) & ((-bitCount) >> 31)
    }

    /// `Random.nextInt(until)`: uniform in 0..<until (until > 0).
    mutating func nextInt(until n: Int32) -> Int32 {
        precondition(n > 0)
        if n & -n == n {
            return nextBits(Int32(31 - n.leadingZeroBitCount))
        }
        var bits: Int32
        var value: Int32
        repeat {
            bits = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> 1)
            value = bits % n
        } while bits &- value &+ (n &- 1) < 0
        return value
    }
}

extension Array {
    /// Kotlin's `shuffled(random)`: a Fisher–Yates shuffle from the end, as `MutableList.shuffle` does it.
    func kotlinShuffled(_ random: inout KotlinRandom) -> [Element] {
        var list = self
        var i = list.count - 1
        while i >= 1 {
            let j = Int(random.nextInt(until: Int32(i + 1)))
            list.swapAt(i, j)
            i -= 1
        }
        return list
    }
}
