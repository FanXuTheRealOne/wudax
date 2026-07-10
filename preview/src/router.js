const version = new URLSearchParams(window.location.search).get('version')
const legacy = version === 'legacy'

if (legacy) {
  document.title = 'WUDAX · 旧版 UI'
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', '#092419')
  import('./main.js')
} else {
  document.title = 'WUDAX · 清新山野 UI'
  import('./fresh.js')
}
