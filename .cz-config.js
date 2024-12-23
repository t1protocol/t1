module.exports = {
  // commit types
  types: [
    { value: "feat", name: "feat:     New feature" },
    { value: "fix", name: "fix:      Bug fix" },
    { value: "test", name: "test:     Add/adjust tests" },
    { value: "docs", name: "docs:     Documentation only changes" },
    {
      value: "WIP",
      name: "WIP:      Work in progress (Use for intermediate commits during EOD;\n            Squash or rebase before merging.)",
    },
    {
      value: "refactor",
      name: "refactor: A code change that neither fixes a bug nor adds a feature",
    },
    {
      value: "chore",
      name: "chore:    Changes to the build process or auxiliary tools\n            and libraries such as documentation generation",
    },
    { value: "revert", name: "revert:   Revert to a commit" },
  ],

  // override the messages, defaults are as follows
  messages: {
    type: "Select the type of change that you're committing:",
    scope:
      "\nWhat is the scope of this change (e.g. component or file name): (press enter to skip)",
    // used if allowCustomScopes is true
    customScope: "What is the scope of this change:",
    subject: "Write a short, imperative tense description of the change:\n",
    body: 'Provide a longer description of the change (optional). Use "|" to break new line:\n',
    breaking: "List any breaking changes (optional):\n",
    footer: "List your associated issue or task (optional):\n",
    confirmCommit: "Are you sure you want to proceed with the commit above?",
  },

  // settings
  allowCustomScopes: false,
  allowBreakingChanges: ["feat", "fix"],

  // skip any questions you want
  skipQuestions: ["customScope"],

  // limit subject length
  subjectLimit: 250,
};
