/**
 * The DOM wiring every calculator page shares, and nothing else.
 *
 * Each calculator page owns its own module script so that the page loads only
 * its own arithmetic — one shared island carrying all of them measured 5,775
 * bytes against an 8,192-byte budget with four calculators in it, and would
 * have exceeded the budget on every calculator page at once with more.
 * `scripts/audit.mjs` enforces that budget per route.
 *
 * Two behaviours here are load-bearing rather than convenience:
 *
 * 1. **The fieldset ships disabled and is enabled from here.** The form has no
 *    `action`, so a submit without JavaScript would GET the current URL with
 *    every field appended — putting a menstrual date into the address bar,
 *    history and any bookmark. Re-enabling it is the signal that a handler now
 *    exists to intercept that submit. A page whose script fails to load stays
 *    un-typeable, which is the safe direction.
 * 2. **A thrown error becomes the error line, never a result.** The compute
 *    functions in `src/lib` reject implausible input by throwing, so the throw
 *    IS the validation path; swallowing it would render a half-built result.
 */

export interface Input {
  /** A field's value, '' when the field is absent or empty. */
  str(name: string): string
  /** A field's value as a number. Every consumer range-checks it and throws. */
  num(name: string): number
  /** Whether a checkbox is ticked. */
  on(name: string): boolean
}

/**
 * Wire `#calc` up to a render function that returns the result markup.
 *
 * The render function is handed the submitted values and must be pure with
 * respect to the DOM: it returns HTML, it does not write it. That keeps every
 * page's arithmetic testable without a browser.
 */
export function mount(render: (v: Input) => string): void {
  const form = document.getElementById('calc') as HTMLFormElement | null
  if (!form) return
  // Safe to accept input now: the handler below keeps every value on this device.
  document.getElementById('calc-fields')?.removeAttribute('disabled')
  const out = document.getElementById('result')!
  const err = document.getElementById('error')!

  form.addEventListener('submit', (e) => {
    e.preventDefault()
    err.textContent = ''
    out.innerHTML = ''
    // Pages that pre-render result tables reveal `#derived` on success. Hide it
    // again first: otherwise a bad submit after a good one leaves last time's
    // dates on screen next to an error message, which reads as the error applying
    // to some other part of the page.
    const derived = document.getElementById('derived')
    if (derived) derived.hidden = true
    const f = new FormData(form)
    const v: Input = {
      str: (n) => String(f.get(n) ?? ''),
      num: (n) => Number(f.get(n)),
      on: (n) => f.get(n) !== null,
    }
    try {
      out.innerHTML = render(v)
    } catch (e) {
      err.textContent = e instanceof Error ? e.message : 'Please check the values you entered.'
    }
  })
}
