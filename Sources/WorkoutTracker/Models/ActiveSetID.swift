/// The address of one Set inside a Session, by the order of its Exercise and the Set's index within
/// it. The rest timer, the Live Activity and the Set Card all name a Set with this, so it is an
/// address rather than focus state.
struct ActiveSetID: Equatable, Hashable, Sendable {
    let exerciseOrder: Int
    let setIndex: Int
}
