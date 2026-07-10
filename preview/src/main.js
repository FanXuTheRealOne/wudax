import './style.css'

const screens = ['home', 'plan', 'gate', 'trip', 'checkin', 'retreat', 'review']
const labels = {
  home: '行程',
  plan: '行前确认',
  gate: '出发守门',
  trip: '行中',
  checkin: '状态问询',
  retreat: '撤退决策',
  review: '复盘',
}

const state = {
  screen: 'home',
  water: 2.5,
  knee: 0,
  drowsy: 0,
  returned: false,
}

const app = document.querySelector('#app')

function routeLine(position = 46) {
  return `
    <div class="route-line" aria-label="路线海拔走势">
      <svg viewBox="0 0 420 74" role="img" aria-label="当前位置位于路线 ${position}%">
        <path d="M0,60 C34,57 54,51 76,47 S118,24 148,30 S191,8 221,18 S266,32 300,24 S354,40 420,12" />
        <circle cx="${position * 4.2}" cy="${position < 48 ? 32 : 23}" r="6" />
      </svg>
    </div>`
}

function header() {
  return `
    <header class="topbar">
      <div class="brand">wuda<span>X</span></div>
      <span class="preview-tag">浏览器预览 · 自动刷新</span>
      <button class="icon-btn" data-action="profile" aria-label="个人资料">◌</button>
    </header>`
}

function metrics(items) {
  return `<div class="metrics">${items.map(item => `
    <div class="metric"><strong>${item.value}</strong><span>${item.label}</span></div>`).join('')}</div>`
}

function actions(items) {
  return `<div class="actions">${items.map(item => `
    <button class="${item.primary ? 'primary' : 'secondary'}" data-go="${item.go}">${item.label}</button>`).join('')}</div>`
}

function home() {
  return `
    <section class="screen home-screen">
      <div class="mountains" aria-hidden="true"><span></span><span></span><span></span></div>
      <p class="eyebrow">离线徒步风险管理</p>
      <h1>行程</h1>
      <div class="accent"></div>
      <article class="route-card light-card">
        <p class="route-name">武功山 · 龙山村—发云界</p>
        ${metrics([
          { value: '24.6 km', label: '路线距离' },
          { value: '1,780 m', label: '累计爬升' },
          { value: '9 h 30 m', label: '预计耗时' },
        ])}
        <div class="card-foot"><span class="risk-chip">▲ 中高风险</span><button class="dark-button" data-go="plan">开始规划</button></div>
      </article>
      <button class="outline-button" data-action="import">导入 GPX 路线</button>
      <section class="profile-section">
        <div class="section-heading"><h2>疲劳档案</h2><span>已记录 3 次行程</span></div>
        <div class="profile-grid">
          <article class="profile-card"><span class="green-icon">♧</span><strong>8.5 km</strong><p>下坡耐受</p><small>累计下降后膝痛出现</small></article>
          <article class="profile-card"><span class="green-icon">◈</span><strong>0.35 L/h</strong><p>补给习惯</p><small>平均耗水速率</small></article>
        </div>
      </section>
    </section>`
}

function plan() {
  return `
    <section class="screen compact-screen">
      <p class="eyebrow">行前确认 · 1 / 3</p>
      <h1>你预计几点出发？</h1>
      <p class="muted">日落前需保留至少 90 分钟返程余量。</p>
      <article class="dark-card">
        <p class="route-name">武功山 · 龙山村—发云界</p>
        ${metrics([{ value: '24.6 km', label: '路线' }, { value: '1,780 m', label: '爬升' }, { value: '中高', label: '挑战' }])}
      </article>
      <div class="choice-list">
        <button class="secondary" data-go="gate">05:30 出发</button>
        <button class="primary" data-go="gate">06:00 出发</button>
        <button class="secondary" data-go="gate">06:30 出发</button>
      </div>
    </section>`
}

function gate() {
  return `
    <section class="screen compact-screen">
      <p class="eyebrow">出发守门</p>
      <h1>补给余量尚可，但路线风险偏高</h1>
      <article class="light-card decision-card">
        <p class="warning">建议至少携带 3.0 L 水；当前计划 2.5 L。请确认头灯、离线地图与备用食物。</p>
        ${metrics([{ value: '2.5 L', label: '当前饮水' }, { value: '3.0 L', label: '建议下限' }, { value: '19:12', label: '日落' }])}
      </article>
      ${actions([{ label: '接受风险并出发', go: 'trip', primary: true }, { label: '调整计划', go: 'plan' }])}
    </section>`
}

function trip() {
  return `
    <section class="screen compact-screen">
      <p class="eyebrow"><span class="live-dot"></span>行程进行中 · 距日落 4 h 18 m</p>
      <h1>已完成 11.2 km</h1>
      <article class="dark-card">
        ${routeLine(46)}
        ${metrics([{ value: '−18 min', label: '计划偏差' }, { value: '1.2 L', label: '剩余饮水' }, { value: '中等', label: '疲劳等级' }])}
        <p class="warning">前方 800 m 进入连续长下坡，建议在下坡前确认膝盖与困倦状态。</p>
      </article>
      ${actions([{ label: '进行状态确认', go: 'checkin', primary: true }, { label: '查看撤退窗口', go: 'retreat' }])}
    </section>`
}

function checkin() {
  return `
    <section class="screen compact-screen">
      <p class="eyebrow">长下坡前确认</p>
      <h1>现在的身体状态怎么样？</h1>
      <article class="dark-card checkin-card">
        <label>剩余饮水 <output>${state.water.toFixed(1)} L</output><input type="range" min="0" max="3" step="0.5" value="${state.water}" data-input="water"></label>
        <label>膝盖疼痛 <output>${state.knee} / 10</output><input type="range" min="0" max="10" step="1" value="${state.knee}" data-input="knee"></label>
        <label>困倦程度 <output>${state.drowsy} / 10</output><input type="range" min="0" max="10" step="1" value="${state.drowsy}" data-input="drowsy"></label>
      </article>
      ${actions([{ label: '提交并重新评估', go: 'retreat', primary: true }, { label: '返回行中', go: 'trip' }])}
    </section>`
}

function retreat() {
  const severe = state.knee >= 5 || state.water <= 1 || state.drowsy >= 5
  return `
    <section class="screen compact-screen">
      <p class="eyebrow ${severe ? 'danger' : ''}">需要决策 · 不可逆点临近</p>
      <h1>${severe ? '建议返程：风险正在叠加' : '建议降级：前往撤离点后返程'}</h1>
      <article class="light-card decision-card">
        <p class="warning">饮水余量、下坡负荷与日落缓冲正在收紧。继续上行会增加夜间下撤风险。</p>
        ${metrics([{ value: '2.1 km', label: '最近撤离点' }, { value: '2 h 12 m', label: '安全返程估计' }, { value: severe ? '红色' : '橙色', label: '风险状态' }])}
      </article>
      ${actions([{ label: '选择返程', go: 'review', primary: true }, { label: '谨慎继续', go: 'trip' }])}
    </section>`
}

function review() {
  return `
    <section class="screen compact-screen">
      <p class="eyebrow">行后复盘</p>
      <h1>${state.returned ? '你在关键节点选择了返程' : '本次行程已完成记录'}</h1>
      <article class="dark-card">
        ${routeLine(72)}
        ${metrics([{ value: '16.5 km', label: '实际距离' }, { value: '6 h 48 m', label: '总时长' }, { value: '3 次', label: '状态确认' }])}
        <p class="muted">下次相似路线：建议增加 0.5 L 饮水余量，并在发云界前完成返程判断。</p>
      </article>
      ${actions([{ label: '返回行程', go: 'home', primary: true }])}
    </section>`
}

const views = { home, plan, gate, trip, checkin, retreat, review }

function navigation() {
  return `<nav class="nav" aria-label="预览页面">${screens.map(name => `
    <button class="${state.screen === name ? 'selected' : ''}" data-go="${name}" aria-current="${state.screen === name ? 'page' : 'false'}">${labels[name]}</button>`).join('')}</nav>`
}

function render() {
  app.innerHTML = `<div class="app-shell">${header()}${navigation()}<main>${views[state.screen]()}</main></div>`

  app.querySelectorAll('[data-go]').forEach(button => {
    button.addEventListener('click', () => {
      if (button.dataset.go === 'review') state.returned = true
      state.screen = button.dataset.go
      render()
    })
  })
  app.querySelectorAll('[data-input]').forEach(input => {
    input.addEventListener('input', event => {
      state[event.target.dataset.input] = Number(event.target.value)
      render()
    })
  })
  app.querySelector('[data-action="import"]')?.addEventListener('click', () => {
    window.alert('浏览器预览模式：GPX 导入将在 iOS App 中处理。这里先模拟导入后的行前规划流程。')
    state.screen = 'plan'
    render()
  })
}

render()
