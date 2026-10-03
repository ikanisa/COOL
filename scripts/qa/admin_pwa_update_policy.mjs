// Browser QA only: model explicitly closing every controlled Admin tab/window.
// Production never invokes these navigations or reloads unfinished operator work.
export async function observeWaitingAdminUpdate(page) {
  return page.evaluate(async () => {
    const registration = await navigator.serviceWorker.ready;
    const previous = navigator.serviceWorker.controller;
    await registration.update();
    const deadline = Date.now() + 30000;
    while (!registration.waiting && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    if (!registration.waiting) throw Error('Admin update did not enter the waiting phase');
    return { state: registration.waiting.state, sameController: navigator.serviceWorker.controller === previous };
  });
}

export async function reopenAfterAllAdminTabsLeave(context, origin) {
  const pages = context.pages().filter((page) => !page.isClosed() && page.url().startsWith(origin + '/'));
  if (!pages.length) throw Error('No Admin browser tabs to close');
  const destinations = pages.map((page) => page.url());
  for (const page of pages) await page.goto('about:blank');
  const deadline = Date.now() + 30000;
  let activated = false;
  while (!activated && Date.now() < deadline) {
    for (const worker of context.serviceWorkers()) {
      try {
        activated = await worker.evaluate(() => !self.registration.waiting && self.registration.active?.state === 'activated');
        if (activated) break;
      } catch { /* The retired worker's execution context is gone. */ }
    }
    if (!activated) await new Promise((resolve) => setTimeout(resolve, 50));
  }
  if (!activated) throw Error('Admin update did not activate after every scoped tab left');
  for (let index = 0; index < pages.length; index++) await pages[index].goto(destinations[index], { waitUntil: 'domcontentloaded' });
}
