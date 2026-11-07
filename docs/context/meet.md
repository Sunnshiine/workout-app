# Workout App glossary: Meet

Part of the domain glossary in [CONTEXT.md](../../CONTEXT.md), which indexes every term. A Meet is
the competition day the coach plans outside the training Sheet. It lives on the phone alone and
never reaches the Sheet (ADR-0001 still holds, because nothing the coach wrote changes).

### Meet

**Meet**: One competition an athlete enters: its calendar date, its Federation Rules, how many lifters share the athlete's Flight, the Attempts the coach called for each Main Lift, and the athlete's Rack Heights and Warm-up Room Plan. The phone holds one at a time, kept locally and never written to the Sheet. Its weights are kilograms, as the platform's are, and stay apart from a Set Log's pounds. A Main Lift with no Attempt is not on that Meet's day, so a bench-only Meet needs no setting. The app records, computes, and reports it. It never picks an Attempt, estimates odds, or scores it with a formula. Avoid: competition, contest.

**Attempt**: One of up to three tries at a Main Lift on the platform, called opener, second, and third by its place. It holds the coach's kilograms and a state: planned, submitted once the card is in, then good or no lift from the referees' lights. An opener is declared at weigh-in, outside the app, so it stays planned until the athlete marks it. An Attempt not called yet does not exist, so a coach who calls the second after seeing the opener leaves it blank, and the athlete enters it in the Attempt Window. Passing drops the Attempts left in that Main Lift, so a Meet can hold no third deadlift. Avoid: rep, try, lift, set.

**Flight**: The lifters who take the platform together for all of a Main Lift's rounds, in order of the weight on the bar. The app holds only how many lifters share the athlete's. It knows nothing of the running order, because no federation publishes one the phone can read, so the athlete counts it on Attempts Out. Avoid: group, session, which name other things here.

**Federation Rules**: One federation's rulebook as a row of values, each with its rule number: how long an Attempt Window runs, what the table enters when it closes, how many changes an opener and a third deadlift allow and until when, what multiples the bar and a record may take, and how long the interval between lifts runs. IPF and USAPL have a row. A value the 2026 rulebook does not state is left out, not guessed. Avoid: ruleset, federation config.

**Attempts Out**: How many Attempts the platform will take before the athlete's own, as the athlete counts it with one large stepper. A mark sets it to one round of the Flight as an estimate, and the next Main Lift's opener sets it to where its Warm-up Room Plan starts. It is always the athlete's count, never the meet's feed. Zero means the athlete is on the platform. Avoid: lifters out, flight position, queue position.

**Warm-up Room Plan**: A Main Lift's warm-up on the day, as a table of steps: the kilograms, the reps, and the Attempts Out at which the athlete takes it. The athlete types the coach's table, or starts from the even steps between the empty bar and the opener and changes any of them. It is the competition-day table, counted in Attempts Out, and is not a Session's warm-up. Avoid: warm-up ladder, warm-up set.

**Attempt Window**: The one minute after the referees' lights in which a second or third Attempt must reach the table, started by the tap that marks the Attempt before it. Its rule shows as it nears zero: with no card the table enters 2.5 kg more after a good lift, or the same weight after a no lift. The phone cannot see the card reach the table, so when the window closes it asks, and either answer submits the next Attempt. Avoid: submission timer, attempt timer, card clock.

**Rack Height**: The athlete's rack settings for a Main Lift, as they wrote them on the weigh-in sheet, such as `14, racks in` or `8, safety 4, blocks`. Plain text, because the numbers belong to that federation's racks. A deadlift has none. Avoid: rack setting, rack position.
