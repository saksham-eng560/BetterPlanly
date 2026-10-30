import { QueryClient } from "@tanstack/react-query";

export const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 15_000, refetchOnWindowFocus: true, retry: 1 } },
});

/** Everything that shows tasks or history re-renders through these two keys. */
export function refreshPlan() {
  return Promise.all([
    queryClient.invalidateQueries({ queryKey: ["tasks"] }),
    queryClient.invalidateQueries({ queryKey: ["history"] }),
    queryClient.invalidateQueries({ queryKey: ["state"] }),
  ]);
}
