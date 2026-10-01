// Keep native disclosures usable without JavaScript; enhance direct case links.
function revealHashTarget() {
  const target = document.getElementById(location.hash.slice(1));
  if (!target) return;
  const disclosure = target.closest('details') || (target.matches('.project-card') ? target.querySelector('details') : null);
  if (disclosure) disclosure.open = true;
  requestAnimationFrame(() => target.scrollIntoView({ block: 'start' }));
}
window.addEventListener('hashchange', revealHashTarget);
if (location.hash) revealHashTarget();

let printState = [];
window.addEventListener('beforeprint', () => {
  printState = [...document.querySelectorAll('details')].map(element => ({ element, open: element.open }));
  printState.forEach(({ element }) => { element.open = true; });
});
window.addEventListener('afterprint', () => {
  printState.forEach(({ element, open }) => { element.open = open; });
});

const financialDialog = document.getElementById('financial-dialog');
const companyCardButton = document.querySelector('.company-card-button');
if (financialDialog && companyCardButton) {
  const closeButton = financialDialog.querySelector('.financial-close');
  const closeFinancialDialog = () => {
    if (!financialDialog.open || financialDialog.classList.contains('is-closing')) return;
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      financialDialog.classList.add('is-closing');
      window.setTimeout(() => financialDialog.close(), 280);
    } else {
      financialDialog.close();
    }
  };
  companyCardButton.addEventListener('click', () => financialDialog.showModal());
  closeButton.addEventListener('click', closeFinancialDialog);
  financialDialog.addEventListener('click', event => {
    if (event.target === financialDialog) closeFinancialDialog();
  });
  financialDialog.addEventListener('cancel', event => {
    event.preventDefault();
    closeFinancialDialog();
  });
  financialDialog.addEventListener('close', () => {
    financialDialog.classList.remove('is-closing');
    companyCardButton.focus();
  });
}

const motionAllowed = !window.matchMedia('(prefers-reduced-motion: reduce)').matches;
if (motionAllowed && 'IntersectionObserver' in window) {
  const sections = document.querySelectorAll('.scroll-reveal');
  const sectionObserver = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      entry.target.classList.toggle('is-visible', entry.isIntersecting);
    });
  }, { threshold: 0.07, rootMargin: '0px 0px 60px 0px' });
  sections.forEach(section => sectionObserver.observe(section));
  document.documentElement.classList.add('motion-ready');
}

const flowRegion = document.querySelector('main.flow-region');
if (flowRegion && motionAllowed) {
  let flowFrame = 0;
  const updateFlow = () => {
    flowFrame = 0;
    const bounds = flowRegion.getBoundingClientRect();
    const progress = Math.max(0, Math.min(1,
      (window.innerHeight - bounds.top) / (window.innerHeight + bounds.height)
    ));
    flowRegion.style.setProperty('--flow-y', `${12 + progress * 70}%`);
  };
  const requestFlowUpdate = () => {
    if (!flowFrame) flowFrame = requestAnimationFrame(updateFlow);
  };
  window.addEventListener('scroll', requestFlowUpdate, { passive: true });
  window.addEventListener('resize', requestFlowUpdate);
  requestFlowUpdate();
}
