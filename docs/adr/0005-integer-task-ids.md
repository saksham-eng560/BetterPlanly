# Integer task ids

Tasks use small serial integer ids (`#12`) instead of UUIDs, because the agent reads and writes ids in tool calls and local 7B models frequently corrupt long random strings. Ids are never exposed outside the single-user install, so their guessability is irrelevant.
