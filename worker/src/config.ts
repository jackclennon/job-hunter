export const SCORING_MODEL = "claude-haiku-5-5";
export const DRAFTING_MODEL = "claude-sonnet-5-5";
export const PRICES_USD_PER_MILLION_TOKENS = {
  "claude-haiku-5-5": { input: 0.10, output: 0.50 },
  "claude-sonnet-5-5": { input: 2, output: 10 },
};
export const TASKS_PER_RUN = 6;
export const RESULTS_PER_SEARCH = 25;
export const MAX_JOBS_SCORED_PER_USER_PER_DAY = 50;
export const MAX_SEARCH_TERMS = 10;
export const MAX_CV_FILES = 6;
export const MAX_CV_FILE_BYTES = 1_000_000;
