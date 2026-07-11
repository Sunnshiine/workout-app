// Shared quiz behaviour for the deep-module-interfaces course.
//
// Markup contract (see course.css for styling):
//   <div class="quiz">
//     <h3>Check yourself</h3>
//     <p class="q">Question text?</p>
//     <button class="choice" data-correct>Right answer</button>
//     <button class="choice">Wrong answer</button>
//     <div class="explain">Shown after any choice is clicked.</div>
//     ... (repeat .q / .choice / .explain groups)
//   </div>
//
// Feedback is immediate: clicking marks the clicked button right/wrong,
// reveals which was correct, shows the explanation, and locks the group.

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.quiz').forEach((quiz) => {
    // Group choices by their question: a group is the run of .choice buttons
    // between one .q and the next.
    let group = [];
    const groups = [];
    quiz.querySelectorAll('.q, .choice, .explain').forEach((el) => {
      if (el.classList.contains('q')) {
        group = { choices: [], explain: null };
        groups.push(group);
      } else if (el.classList.contains('choice')) {
        group.choices.push(el);
      } else if (el.classList.contains('explain')) {
        group.explain = el;
      }
    });

    groups.forEach(({ choices, explain }) => {
      choices.forEach((btn) => {
        btn.addEventListener('click', () => {
          if (choices.some((c) => c.disabled)) return; // already answered
          choices.forEach((c) => {
            c.disabled = true;
            if (c.hasAttribute('data-correct')) c.classList.add('correct');
          });
          if (!btn.hasAttribute('data-correct')) btn.classList.add('wrong');
          if (explain) explain.classList.add('shown');
        });
      });
    });
  });
});
