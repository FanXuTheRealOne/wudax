import './fresh.css'

const screens = ['home', 'plan', 'gate', 'trip', 'checkin', 'retreat', 'review']
const labels = {
  home: '首页',
  plan: '行前',
  gate: '守门',
  trip: '行中',
  checkin: '问询',
  retreat: '下撤',
  review: '复盘',
}

const state = {
  screen: 'home',
  departure: '06:00',
  plannedWater: 2.5,
  water: 1.2,
  knee: 2,
  drowsy: 1,
  returned: false,
}

const app = document.querySelector('#app')

const iconPaths = {
  back: '<path d="m15 18-6-6 6-6"/><path d="M9 12h10"/>',
  profile: '<circle cx="12" cy="8" r="3.2"/><path d="M5.7 20c.7-4 2.8-6 6.3-6s5.6 2 6.3 6"/>',
  cloud: '<path d="M7 18h10a4 4 0 0 0 .5-8 6 6 0 0 0-11-1.5A4.8 4.8 0 0 0 7 18Z"/>',
  offline: '<path d="M4.9 4.9a10 10 0 0 1 14.2 0"/><path d="M7.8 7.8a6 6 0 0 1 8.4 0"/><path d="M10.7 10.7a2 2 0 0 1 2.6 0"/><path d="M12 15h.01"/><path d="m3 3 18 18"/>',
  route: '<circle cx="6" cy="18" r="2"/><circle cx="18" cy="6" r="2"/><path d="M7.7 16.9c3.1-1.9 1.5-5.1 4.4-6.2 2.1-.8 3.4.2 4.6-2.8"/>',
  mountain: '<path d="m3 20 6.5-12 4 7 2.2-4L21 20Z"/><path d="m7.7 11.4 1.8 1.1 1.6-1.4"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3.2 2"/>',
  sunrise: '<path d="M4 18h16"/><path d="M6 15a6 6 0 0 1 12 0"/><path d="M12 3v3M4.2 7.2l2.1 2.1M19.8 7.2l-2.1 2.1"/>',
  water: '<path d="M12 3s6 6.2 6 11a6 6 0 0 1-12 0c0-4.8 6-11 6-11Z"/><path d="M9 15c.5 1.3 1.5 2 3 2"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  alert: '<path d="M10.2 4.5 3.4 17a2 2 0 0 0 1.8 3h13.6a2 2 0 0 0 1.8-3L13.8 4.5a2 2 0 0 0-3.6 0Z"/><path d="M12 9v4M12 17h.01"/>',
  locate: '<circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="8"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2"/>',
  compass: '<circle cx="12" cy="12" r="9"/><path d="m15.5 8.5-2 5-5 2 2-5 5-2Z"/>',
  knee: '<path d="M9 3v6l3 3-2 9"/><path d="M15 3v7l-3 2 3 3v6"/><circle cx="12" cy="12" r="2"/>',
  moon: '<path d="M19 15.5A8 8 0 0 1 8.5 5 8.2 8.2 0 1 0 19 15.5Z"/>',
  leaf: '<path d="M20 4C11 4 5 8 5 14c0 3 2 5 5 5 6 0 10-6 10-15Z"/><path d="M4 21c3-5 7-8 13-11"/>',
  chevron: '<path d="m9 18 6-6-6-6"/>',
  file: '<path d="M6 3h8l4 4v14H6Z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>',
  shield: '<path d="M12 3 5 6v5c0 4.6 2.8 8 7 10 4.2-2 7-5.4 7-10V6Z"/><path d="m9 12 2 2 4-4"/>',
}

function icon(name, className = '') {
  return `<svg class="icon ${className}" viewBox="0 0 24 24" aria-hidden="true">${iconPaths[name]}</svg>`
}

function previewBar() {
  return `
    <aside class="preview-bar" aria-label="设计稿导航">
      <div class="preview-copy">
        <span class="preview-dot"></span>
        <span><strong>清新山野</strong> · 方案 B</span>
      </div>
      <nav class="screen-tabs" aria-label="快速切换页面">
        ${screens.map(name => `<button type="button" data-go="${name}" class="${state.screen === name ? 'is-active' : ''}">${labels[name]}</button>`).join('')}
      </nav>
      <a class="legacy-link" href="/?version=legacy">查看旧版 A</a>
    </aside>`
}

function appHeader({ back = null, title = '', transparent = false } = {}) {
  return `
    <header class="app-header ${transparent ? 'on-image' : ''}">
      <div class="header-side">
        ${back
          ? `<button type="button" class="round-button" data-go="${back}" aria-label="返回">${icon('back')}</button>`
          : `<div class="wordmark"><span>wuda</span><b>X</b></div>`}
      </div>
      ${title ? `<span class="header-title">${title}</span>` : '<span></span>'}
      <div class="header-side right">
        ${back
          ? '<span class="offline-mini">离线可用</span>'
          : `<button type="button" class="round-button" aria-label="个人档案">${icon('profile')}</button>`}
      </div>
    </header>`
}

function progressSteps(active) {
  return `<div class="stage-progress" aria-label="行前评估进度 ${active} / 3"><span class="active"></span><span class="${active >= 2 ? 'active' : ''}"></span><span class="${active >= 3 ? 'active' : ''}"></span></div>`
}

function elevationChart(position = 46, dangerPoint = 68) {
  return `
    <svg class="elevation-chart" viewBox="0 0 420 116" role="img" aria-label="路线海拔剖面，当前完成 ${position}%">
      <defs>
        <linearGradient id="fresh-area" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="currentColor" stop-opacity=".22"/>
          <stop offset="1" stop-color="currentColor" stop-opacity="0"/>
        </linearGradient>
      </defs>
      <path class="chart-grid" d="M10 92H410M10 59H410M10 26H410"/>
      <path class="chart-area" d="M10 92C45 82 55 73 80 70s44-35 72-28 33-24 58-18 40 23 66 28 34 22 58 18 40 10 76-22V104H10Z"/>
      <path class="chart-line" d="M10 92C45 82 55 73 80 70s44-35 72-28 33-24 58-18 40 23 66 28 34 22 58 18 40 10 76-22"/>
      <path class="chart-progress" pathLength="100" stroke-dasharray="${position} 100" d="M10 92C45 82 55 73 80 70s44-35 72-28 33-24 58-18 40 23 66 28 34 22 58 18 40 10 76-22"/>
      <line class="danger-line" x1="${dangerPoint * 4.0 + 10}" y1="16" x2="${dangerPoint * 4.0 + 10}" y2="102"/>
      <circle class="current-point" cx="${position * 4.0 + 10}" cy="${position < 50 ? 42 : 70}" r="5"/>
    </svg>`
}

function topoMap() {
  return `
    <svg class="topo-map" viewBox="0 0 430 330" role="img" aria-label="GPX 路线地图，当前位置在路线中段">
      <g class="contours">
        <path d="M-20 66C50 4 113 25 145 62s66 39 108 10 105-34 200 13"/>
        <path d="M-28 91C34 32 104 44 135 80s72 46 120 15 111-37 202 10"/>
        <path d="M-25 119c64-51 118-45 156-10s75 36 124 7 111-27 192 20"/>
        <path d="M-12 274c56-53 93-69 147-45s75 25 112-6 101-52 196-12"/>
        <path d="M-30 300c56-45 100-58 151-36s87 26 129-8 107-45 197-3"/>
        <path d="M48 159c44-27 84-29 110-3s16 61 52 78 75-7 103-36 67-28 111 3"/>
        <path d="M62 181c32-22 61-19 80 2s14 49 45 66 71 9 105-18 72-31 118-4"/>
      </g>
      <path class="route-shadow" d="M48 276c30-38 41-66 70-79 31-14 48 8 68-17 22-27 4-54 35-71 34-18 54 16 88-3 27-15 39-43 78-48"/>
      <path class="route-path" d="M48 276c30-38 41-66 70-79 31-14 48 8 68-17 22-27 4-54 35-71 34-18 54 16 88-3 27-15 39-43 78-48"/>
      <circle class="route-start" cx="48" cy="276" r="5"/>
      <circle class="route-current-halo" cx="203" cy="155" r="18"/>
      <circle class="route-current" cx="203" cy="155" r="7"/>
      <g class="map-label" transform="translate(226 124)"><rect width="108" height="36" rx="12"/><text x="14" y="23">当前位置 · 46%</text></g>
      <g class="risk-pin" transform="translate(301 76)"><circle r="13"/><path d="M0-5v6M0 6h.01"/></g>
    </svg>`
}

function home() {
  return `
    <section class="app-screen home-screen">
      <div class="home-hero">
        ${appHeader({ transparent: true })}
        <div class="hero-wash"></div>
        <div class="hero-content">
          <div class="weather-line">${icon('cloud')} 17–23°C · 多云转晴</div>
          <p>周六 · 7 月 18 日</p>
          <h1>武功山<br><span>龙山村—发云界</span></h1>
          <div class="hero-status"><span>挑战偏高</span><small>适合有长距离经验的人</small></div>
        </div>
      </div>

      <div class="home-body page-padding">
        <div class="route-facts" aria-label="路线信息">
          <div><span>距离</span><strong>24.6<small> km</small></strong></div>
          <div><span>累计爬升</span><strong>1,780<small> m</small></strong></div>
          <div><span>预计耗时</span><strong>9<small> h 30 m</small></strong></div>
        </div>

        <div class="elevation-wrap">
          ${elevationChart(0, 68)}
          <div class="chart-labels"><span>龙山村 · 420m</span><span>发云界 · 1,910m</span></div>
        </div>

        <div class="primary-stack">
          <button type="button" class="main-action" data-go="plan"><span>开始行前评估</span>${icon('chevron')}</button>
          <button type="button" class="quiet-action" data-action="import">${icon('file')} 导入其他 GPX 路线</button>
        </div>

        <section class="profile-strip">
          <div class="section-label"><span>你的疲劳基线</span><small>来自最近 3 次行程</small></div>
          <div class="profile-row">
            <div class="profile-symbol">${icon('knee')}</div>
            <div><strong>长下坡后容易出现膝部不适</strong><span>建议在累计下降 800m 前主动确认</span></div>
            ${icon('chevron')}
          </div>
        </section>
      </div>
    </section>`
}

function plan() {
  return `
    <section class="app-screen light-screen">
      ${appHeader({ back: 'home', title: '行前评估' })}
      <div class="page-padding content-stack">
        ${progressSteps(1)}
        <div class="question-heading">
          <span class="nature-mark">${icon('sunrise')}</span>
          <p>时间余量</p>
          <h1>今天准备几点<br>从龙山村出发？</h1>
          <span>出发时间会影响日照余量和最晚折返点。</span>
        </div>

        <div class="context-note">
          <div>${icon('sunrise')}<span><small>今日日落</small><strong>19:12</strong></span></div>
          <p>建议在日落前至少 90 分钟抵达公路或营地。</p>
        </div>

        <div class="time-options" role="group" aria-label="选择出发时间">
          ${['05:30', '06:00', '06:30'].map(time => `
            <button type="button" data-time="${time}" class="time-option ${state.departure === time ? 'selected' : ''}">
              <span><strong>${time}</strong><small>${time === '05:30' ? '日照余量最充足' : time === '06:00' ? '推荐 · 余量充足' : '需要更严格控速'}</small></span>
              <i></i>
            </button>`).join('')}
        </div>

        <button type="button" class="main-action" data-go="gate"><span>继续评估补给</span>${icon('chevron')}</button>
        <button type="button" class="text-action" data-go="gate">跳到出发检查</button>
      </div>
    </section>`
}

function gate() {
  const enoughWater = state.plannedWater >= 3
  return `
    <section class="app-screen light-screen">
      ${appHeader({ back: 'plan', title: '出发检查' })}
      <div class="page-padding content-stack gate-content">
        ${progressSteps(3)}
        <div class="decision-heading ${enoughWater ? 'ready' : ''}">
          <span class="decision-icon">${icon(enoughWater ? 'shield' : 'water')}</span>
          <p>${enoughWater ? '准备完成' : '出发前还差一步'}</p>
          <h1>${enoughWater ? '关键资源已就绪' : '请再增加 0.5L 饮水'}</h1>
          <span>${enoughWater ? '路线偏长，途中仍需按计划检查补给和身体状态。' : '按你的补水习惯和预计耗时，2.5L 会在返程前跌破安全余量。'}</span>
        </div>

        <section class="water-budget">
          <div class="water-header">
            <span>${icon('water')} 饮水预算</span>
            <strong>${state.plannedWater.toFixed(1)}<small> / 3.0 L</small></strong>
          </div>
          <div class="water-track"><span style="width:${Math.min(100, state.plannedWater / 3 * 100)}%"></span><i></i></div>
          <div class="water-scale"><span>当前携带</span><span>建议下限</span></div>
          ${enoughWater ? '<p class="success-note">已达到建议下限，预计保留约 0.4L 返程余量。</p>' : '<button type="button" class="add-water" data-add-water>我已增加 0.5L 饮水 <span>＋</span></button>'}
        </section>

        <section class="readiness-list" aria-label="离线资源检查">
          <div class="section-label"><span>出发条件</span><small>4 项本地检查</small></div>
          <div class="check-row">${icon('check')}<span><strong>GPX 路线</strong><small>10,477 个轨迹点已保存</small></span><b>就绪</b></div>
          <div class="check-row">${icon('check')}<span><strong>定位与通知</strong><small>精确定位已允许</small></span><b>就绪</b></div>
          <div class="check-row">${icon('check')}<span><strong>离线模式</strong><small>路线、海拔和规则无需网络</small></span><b>就绪</b></div>
          <div class="check-row muted-check">${icon('alert')}<span><strong>路线挑战</strong><small>高于近期最长距离 28%</small></span><b>留意</b></div>
        </section>

        <button type="button" class="main-action ${enoughWater ? '' : 'soft-disabled'}" data-go="trip"><span>${enoughWater ? '确认并开始行程' : '接受补给风险并出发'}</span>${icon('chevron')}</button>
        <button type="button" class="text-action" data-go="plan">返回调整计划</button>
      </div>
    </section>`
}

function trip() {
  return `
    <section class="app-screen trip-screen">
      <div class="map-stage">
        ${topoMap()}
        ${appHeader({ title: '武功山 · 行程中', transparent: true })}
        <div class="map-status"><span class="live-pulse"></span><strong>在轨迹上</strong><small>定位可信度高</small></div>
        <button type="button" class="map-control" aria-label="定位到当前位置">${icon('locate')}</button>
      </div>

      <div class="trip-sheet">
        <div class="sheet-handle"></div>
        <div class="trip-heading">
          <div><p>已行进 3 h 46 m</p><h1>11.2 <small>km</small></h1></div>
          <div class="progress-ring" style="--progress:46"><strong>46%</strong><span>路线进度</span></div>
        </div>
        <div class="trip-metrics">
          <div><span>剩余距离</span><strong>13.4 km</strong></div>
          <div><span>剩余爬升</span><strong>820 m</strong></div>
          <div><span>距日落</span><strong>4 h 18 m</strong></div>
        </div>
        <section class="next-risk">
          <span class="risk-icon">${icon('mountain')}</span>
          <div><small>800m 后 · 长下坡入口</small><strong>进入前确认膝盖和困倦</strong><p>连续下降约 1,200m，预计需要 2 h 10 m。</p></div>
        </section>
        <div class="trip-actions">
          <button type="button" class="main-action" data-go="checkin"><span>现在确认身体状态</span>${icon('chevron')}</button>
          <button type="button" class="map-secondary" data-go="retreat">${icon('compass')} 查看下撤窗口</button>
        </div>
      </div>
    </section>`
}

function scoreLabel(value, type) {
  if (value === 0) return type === 'knee' ? '没有疼痛' : '精神清醒'
  if (value <= 3) return '轻微，不影响行走'
  if (value <= 6) return '明显，需要降速'
  return '严重，影响安全'
}

function checkin() {
  return `
    <section class="app-screen light-screen">
      ${appHeader({ back: 'trip', title: '身体状态' })}
      <div class="page-padding content-stack checkin-content">
        <div class="question-heading compact">
          <span class="nature-mark">${icon('leaf')}</span>
          <p>长下坡前 · 约 30 秒</p>
          <h1>听一下身体<br>现在的反馈</h1>
          <span>这些信息只保存在手机中，用于更新本次行程建议。</span>
        </div>

        <section class="body-question">
          <div class="question-top"><span>${icon('water')}剩余饮水</span><output>${state.water.toFixed(1)} L</output></div>
          <input class="range-control" type="range" min="0" max="2.5" step="0.1" value="${state.water}" data-input="water" aria-label="剩余饮水">
          <div class="range-labels"><span>空</span><span>约 2.5L</span></div>
        </section>

        <section class="body-question">
          <div class="question-top"><span>${icon('knee')}膝盖疼痛</span><output>${state.knee} / 10</output></div>
          <strong class="score-copy">${scoreLabel(state.knee, 'knee')}</strong>
          <input class="range-control" type="range" min="0" max="10" step="1" value="${state.knee}" data-input="knee" aria-label="膝盖疼痛评分">
          <div class="range-labels"><span>无痛</span><span>无法正常行走</span></div>
        </section>

        <section class="body-question">
          <div class="question-top"><span>${icon('moon')}困倦程度</span><output>${state.drowsy} / 10</output></div>
          <strong class="score-copy">${scoreLabel(state.drowsy, 'drowsy')}</strong>
          <input class="range-control" type="range" min="0" max="10" step="1" value="${state.drowsy}" data-input="drowsy" aria-label="困倦程度评分">
          <div class="range-labels"><span>清醒</span><span>难以集中注意</span></div>
        </section>

        <button type="button" class="main-action" data-go="retreat"><span>保存并更新建议</span>${icon('chevron')}</button>
        <button type="button" class="text-action" data-go="trip">暂时跳过</button>
      </div>
    </section>`
}

function retreat() {
  const severe = state.knee >= 5 || state.water <= 1 || state.drowsy >= 5
  return `
    <section class="app-screen retreat-screen">
      ${appHeader({ back: 'trip', title: '下撤建议' })}
      <div class="page-padding content-stack">
        <div class="retreat-heading">
          <span class="risk-level">${severe ? '风险正在叠加' : '安全窗口正在收紧'}</span>
          <h1>${severe ? '建议从当前节点下撤' : '建议在前方岔口下撤'}</h1>
          <p>不是因为某一个指标，而是补给、下坡负荷和日照余量同时接近边界。</p>
        </div>

        <section class="reason-list">
          <div><span class="reason-symbol water">${icon('water')}</span><p><strong>饮水余量偏低</strong><small>${state.water.toFixed(1)}L · 继续路线预计需要 1.7L</small></p><b>${state.water <= 1 ? '高' : '中'}</b></div>
          <div><span class="reason-symbol slope">${icon('mountain')}</span><p><strong>连续长下坡</strong><small>前方累计下降约 1,200m</small></p><b>中</b></div>
          <div><span class="reason-symbol sun">${icon('sunrise')}</span><p><strong>日照缓冲不足</strong><small>按当前速度抵达公路将接近日落</small></p><b>中</b></div>
        </section>

        <section class="recommended-route">
          <div class="recommend-tag">推荐路线</div>
          <div class="route-choice-title"><span>${icon('shield')}</span><div><small>当前节点下撤</small><strong>2.1 km 到公路</strong></div></div>
          <div class="route-timeline">
            <span class="timeline-dot active"></span><i></i><span class="timeline-dot"></span>
            <div><small>现在</small><strong>当前位置</strong></div><div><small>约 52 分钟</small><strong>龙山公路</strong></div>
          </div>
          <div class="safe-arrival">${icon('sunrise')} 预计 17:24 前抵达 · 保留 1 h 48 m 日照</div>
        </section>

        <button type="button" class="retreat-action" data-go="review"><span>${icon('compass')}选择下撤路线</span>${icon('chevron')}</button>
        <button type="button" class="continue-action" data-go="trip">我理解风险，仍然继续</button>
        <p class="decision-footnote">继续不会关闭提醒；风险升级时 WUDAX 会再次提示。</p>
      </div>
    </section>`
}

function review() {
  return `
    <section class="app-screen review-screen">
      <div class="review-hero">
        ${appHeader({ transparent: true })}
        <div class="review-hero-copy"><p>行程已安全结束</p><h1>你在风险收紧前<br>做出了决定</h1><span>下撤不是少走一段，而是为下一次山行保留余量。</span></div>
      </div>
      <div class="page-padding content-stack review-body">
        <div class="review-summary">
          <div><span>实际距离</span><strong>16.5<small> km</small></strong></div>
          <div><span>总时长</span><strong>6<small> h 48 m</small></strong></div>
          <div><span>状态确认</span><strong>3<small> 次</small></strong></div>
        </div>

        <section class="review-chart">
          <div class="section-label"><span>路线完成情况</span><small>计划与实际</small></div>
          ${elevationChart(67, 68)}
          <div class="review-legend"><span><i class="actual"></i>实际终点 · 下撤岔口</span><span><i></i>原计划 · 发云界</span></div>
        </section>

        <section class="insight-card">
          <span class="insight-icon">${icon('leaf')}</span>
          <div><small>本次得到的新线索</small><strong>饮水下降比计划快约 18%</strong><p>下次相似路线建议增加 0.5L，并将第一次主动检查提前到 8km。</p></div>
        </section>

        <section class="reflection">
          <div class="section-label"><span>留给下一次</span><small>可稍后回答</small></div>
          <button type="button"><span>今天什么时候第一次觉得步频变慢？</span>${icon('chevron')}</button>
          <button type="button"><span>下撤决定是否来得及时？</span>${icon('chevron')}</button>
        </section>

        <button type="button" class="main-action" data-go="home"><span>完成复盘</span>${icon('check')}</button>
      </div>
    </section>`
}

const views = { home, plan, gate, trip, checkin, retreat, review }

function render() {
  app.innerHTML = `<div class="fresh-preview">${previewBar()}<main class="app-frame">${views[state.screen]()}</main></div>`

  app.querySelectorAll('[data-go]').forEach(button => {
    button.addEventListener('click', () => {
      if (button.dataset.go === 'review') state.returned = true
      state.screen = button.dataset.go
      window.scrollTo({ top: 0, behavior: 'smooth' })
      render()
    })
  })

  app.querySelectorAll('[data-time]').forEach(button => {
    button.addEventListener('click', () => {
      state.departure = button.dataset.time
      render()
    })
  })

  app.querySelectorAll('[data-input]').forEach(input => {
    input.addEventListener('input', event => {
      state[event.target.dataset.input] = Number(event.target.value)
      render()
    })
  })

  app.querySelector('[data-add-water]')?.addEventListener('click', () => {
    state.plannedWater = 3
    render()
  })

  app.querySelector('[data-action="import"]')?.addEventListener('click', () => {
    window.alert('浏览器设计预览：已模拟导入 GPX，接下来进入行前评估。')
    state.screen = 'plan'
    render()
  })
}

render()
