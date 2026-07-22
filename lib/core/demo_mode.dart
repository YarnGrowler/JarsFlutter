/// Demo Mode: the game runs entirely locally — supply from real logs is added
/// instantly, nights advance when the player presses BEGIN THE NIGHT, teammates
/// are local crew, and the league/standings are computed on-device. No Supabase
/// reads, no wall clock, no debug screen in the play loop.
///
/// The Supabase-backed weekly model (calendar sieges, shared allocation rows)
/// stays in the codebase behind this flag for the future multi-friend release.
/// (A getter, not a const, so flag-gated branches don't trip dead-code lints.)
bool get kDemoMode => true;
