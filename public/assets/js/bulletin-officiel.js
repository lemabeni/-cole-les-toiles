// Bulletin officiel (modèles IGE/P.S.) — fonctions pures : aucune requête réseau ni Supabase ici.
// Le catalogue des cours et des points maximums est dans assets/data/bulletins_officiels.json.

export const PERIOD_LABELS = {
  P1: '1re période', P2: '2e période', P3: '3e période', P4: '4e période', P5: '5e période', P6: '6e période',
  E1: 'Examen 1', E2: 'Examen 2', E3: 'Examen 3'
};

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const normName = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\(1\)/g, '').replace(/[^a-z0-9]+/g, ' ').trim();

/** Termes (trimestres ou semestres) et clés de colonnes d'un régime. */
export function terms(regime) {
  const n = regime === 'trimestre' ? 3 : 2;
  return Array.from({ length: n }, (_, i) => ({ n: i + 1, keys: ['P' + (2 * i + 1), 'P' + (2 * i + 2), 'E' + (i + 1)] }));
}
export const termWord = regime => (regime === 'trimestre' ? 'TRIMESTRE' : 'SEMESTRE');
export const termLabels = regime => (regime === 'trimestre' ? ['PREMIER TRIMESTRE', 'DEUXIÈME TRIMESTRE', 'TROISIÈME TRIMESTRE'] : ['PREMIER SEMESTRE', 'SECOND SEMESTRE']);
export const allKeys = regime => terms(regime).flatMap(t => t.keys);

/** Maxima d'un cours : période (p), examen (e), total d'un terme (t), total annuel (tg). */
export function branchMax(model, b) {
  const p = Number(b.p), e = b.exam === undefined ? 2 * p : Number(b.exam);
  const t = 2 * p + e;
  return { p, e, t, tg: terms(model.regime).length * t };
}
export function maxForKey(model, b, key) {
  const m = branchMax(model, b);
  return key[0] === 'P' ? m.p : m.e;
}
export const flatBranches = model => model.domains.flatMap(d => d.groups.flatMap(g => g.branches));
export const modelTotal = model => flatBranches(model).reduce((s, b) => s + branchMax(model, b).tg, 0);

/** Choix automatique du modèle pour une classe (expressions régulières du catalogue). */
export function findModelForClass(catalogue, cls) {
  const name = String(cls?.class_name || '').trim();
  const sec = String(cls?.section || '').trim();
  const full = (name + ' ' + sec).trim();
  return catalogue.models.find(m => (m.classes || []).some(rx => new RegExp(rx, 'i').test(name) || new RegExp(rx, 'i').test(full))) || null;
}

/** Lie chaque cours du modèle à une matière de la base (même nom, sans accents ni casse). */
export function matchSubjects(model, subjects) {
  const byName = new Map();
  subjects.forEach(s => { const k = normName(s.subject_name); if (!byName.has(k)) byName.set(k, s); });
  const map = new Map();
  flatBranches(model).forEach(b => { const s = byName.get(normName(b.name)); if (s) map.set(b, s); });
  return map;
}

/**
 * Totaux et classement d'une classe.
 * rows : [{ id, getPoints(branch,key) -> nombre | null }]
 * Retourne Map(id -> { cols: { P1:{pts,max,pct}, …, T1:…, TG:… }, rank:{ key: n }, count:{ key: n } })
 * Le pourcentage d'une colonne = points obtenus ÷ maxima des cours effectivement notés dans cette colonne.
 */
export function computeStats(model, rows) {
  const keys = allKeys(model.regime), ts = terms(model.regime), branches = flatBranches(model);
  const res = new Map();
  rows.forEach(r => {
    const cols = {};
    keys.forEach(k => {
      let pts = 0, max = 0, any = false;
      branches.forEach(b => { const v = r.getPoints(b, k); if (v !== null && v !== undefined && v !== '') { pts += Number(v); max += maxForKey(model, b, k); any = true; } });
      cols[k] = any ? { pts, max, pct: max ? 100 * pts / max : null } : null;
    });
    ts.forEach(t => {
      const parts = t.keys.map(k => cols[k]).filter(Boolean);
      cols['T' + t.n] = parts.length ? sumCols(parts) : null;
    });
    const tparts = ts.map(t => cols['T' + t.n]).filter(Boolean);
    cols.TG = tparts.length ? sumCols(tparts) : null;
    res.set(r.id, { cols, rank: {}, count: {} });
  });
  [...keys, ...ts.map(t => 'T' + t.n), 'TG'].forEach(k => {
    const list = [...res.entries()].filter(([, v]) => v.cols[k] && v.cols[k].pct !== null).map(([id, v]) => ({ id, pct: v.cols[k].pct })).sort((a, b) => b.pct - a.pct);
    let last = null, rank = 0;
    list.forEach((x, i) => { if (last === null || Math.abs(x.pct - last) > 1e-9) rank = i + 1; last = x.pct; res.get(x.id).rank[k] = rank; });
    list.forEach(x => { res.get(x.id).count[k] = list.length; });
  });
  return res;
}
const sumCols = parts => { const pts = parts.reduce((s, c) => s + c.pts, 0), max = parts.reduce((s, c) => s + c.max, 0); return { pts, max, pct: max ? 100 * pts / max : null }; };

const num = v => (v === null || v === undefined || v === '' ? '' : (Math.round(Number(v) * 100) / 100).toString().replace('.', ','));
const pct = v => (v === null || v === undefined ? '' : (Math.round(v * 10) / 10).toString().replace('.', ',') + '%');

/** HTML du bulletin (mise en page inspirée du bulletin ministériel A4). */
export function renderBulletin({ model, student, cls, year, school = {}, header = {}, getPoints, stats, editable = false }) {
  const flat = flatBranches(model);
  const ts = terms(model.regime), tl = termLabels(model.regime), keys = allKeys(model.regime);
  const colsPerTerm = 7, totalCols = 1 + ts.length * colsPerTerm + 2;
  const st = stats?.cols || {}, rk = stats?.rank || {}, cnt = stats?.count || {};
  const cellPts = (b, k) => {
    const v = getPoints ? getPoints(b, k) : null;
    if (!editable) return '<td class="ob-v">' + num(v) + '</td>';
    const mx = maxForKey(model, b, k);
    return '<td class="ob-v ob-res"><input class="ob-in" type="text" inputmode="decimal" autocomplete="off" data-b="' + flat.indexOf(b) + '" data-k="' + k + '" data-max="' + mx + '" value="' + esc(num(v)) + '" aria-label="' + esc(b.name + ' — ' + PERIOD_LABELS[k] + ' (sur ' + mx + ')') + '" title="Maximum : ' + mx + '"></td>';
  };
  const branchRow = (b, cls_ = '') => {
    const m = branchMax(model, b);
    let h = '<tr class="' + cls_ + '"><th scope="row" class="ob-name">' + esc(b.name) + (b.optional ? ' <sup>(1)</sup>' : '') + '</th>';
    let tg = 0, any = false;
    ts.forEach(t => {
      const [k1, k2, ke] = t.keys; let tsum = 0, tany = false;
      [k1, k2, ke].forEach(k => { const v = getPoints ? getPoints(b, k) : null; if (v !== null && v !== undefined && v !== '') { tsum += Number(v); tany = true; } });
      h += '<td class="ob-m">' + m.p + '</td>' + cellPts(b, k1) + cellPts(b, k2);
      h += m.e ? '<td class="ob-m">' + m.e + '</td>' + cellPts(b, ke) : '<td class="ob-na"></td><td class="ob-na"></td>';
      h += '<td class="ob-m">' + m.t + '</td><td class="ob-v ob-tot">' + (tany ? num(tsum) : '') + '</td>';
      if (tany) { tg += tsum; any = true; }
    });
    return h + '<td class="ob-m">' + m.tg + '</td><td class="ob-v ob-tot">' + (any ? num(tg) : '') + '</td></tr>';
  };
  const sumRow = (label, list, cls_ = 'ob-sub') => {
    let h = '<tr class="' + cls_ + '"><th scope="row" class="ob-name">' + esc(label) + '</th>';
    let tgm = 0;
    ts.forEach(t => {
      const sp = list.reduce((s, b) => s + branchMax(model, b).p, 0), se = list.reduce((s, b) => s + branchMax(model, b).e, 0), stt = list.reduce((s, b) => s + branchMax(model, b).t, 0);
      h += '<td class="ob-m">' + sp + '</td><td></td><td></td><td class="ob-m">' + (se || '') + '</td><td></td><td class="ob-m">' + stt + '</td><td></td>'; tgm += stt;
    });
    return h + '<td class="ob-m">' + tgm + '</td><td></td></tr>';
  };
  let body = '';
  model.domains.forEach(d => {
    if (d.name) body += '<tr class="ob-dom"><th colspan="' + totalCols + '">' + esc(d.name.toUpperCase()) + '</th></tr>';
    d.groups.forEach(g => {
      const solo = g.branches.length === 1 && g.name && normName(g.name) === normName(g.branches[0].name);
      if (g.name && !solo) body += '<tr class="ob-grp"><th colspan="' + totalCols + '">' + esc(g.name.toUpperCase()) + '</th></tr>';
      if (!d.name && !g.name) { // modèles sans domaines : ligne MAXIMA du groupe, comme sur le papier
        const m = branchMax(model, g.branches[0]);
        body += '<tr class="ob-grp"><th colspan="' + totalCols + '">MAXIMA ' + m.p + ' par période' + (m.e ? ' · examen ' + m.e : ' · pas d’examen') + ' · total annuel ' + m.tg + '</th></tr>';
      }
      g.branches.forEach(b => { body += branchRow(b); });
      if ((d.name || g.name) && g.branches.length > 1) body += sumRow('Sous-total', g.branches);
    });
  });
  const all = flatBranches(model);
  const maxGen = sumRow('MAXIMA GÉNÉRAUX', all, 'ob-gen');
  // pieds de tableau : totaux, pourcentage, place, effectif
  const footRow = (label, fn) => {
    let h = '<tr class="ob-foot"><th scope="row" class="ob-name">' + label + '</th>';
    ts.forEach(t => {
      const [k1, k2, ke] = t.keys, tk = 'T' + t.n;
      h += '<td class="ob-na"></td><td class="ob-v">' + fn(k1) + '</td><td class="ob-v">' + fn(k2) + '</td><td class="ob-na"></td><td class="ob-v">' + fn(ke) + '</td><td class="ob-na"></td><td class="ob-v ob-tot">' + fn(tk) + '</td>';
    });
    return h + '<td class="ob-na"></td><td class="ob-v ob-tot">' + fn('TG') + '</td></tr>';
  };
  const blank = label => '<tr class="ob-foot"><th scope="row" class="ob-name">' + label + '</th><td colspan="' + (totalCols - 1) + '" class="ob-edit"></td></tr>';
  const foot = footRow('TOTAUX', k => (st[k] ? num(st[k].pts) : '')) + footRow('POURCENTAGE', k => (st[k] ? pct(st[k].pct) : '')) +
    footRow('PLACE', k => (rk[k] ? rk[k] + (rk[k] === 1 ? 'er' : 'e') : '')) + footRow('NBRE D’ÉLÈVES', k => (cnt[k] || '')) +
    blank('APPLICATION') + blank('CONDUITE') + (model.regime === 'trimestre' ? blank('SIGNAT. DE L’INST.') : '') + blank('SIGNAT. DU RESP.');
  const fb = model.finalBlock ? '<table class="ob-final"><caption>' + esc(model.finalBlock.title) + '</caption>' + model.finalBlock.rows.map(r => '<tr><th>' + esc(r[0]) + '</th><td>' + (r[1] ?? '') + '</td><td class="ob-edit"></td></tr>').join('') + '</table>' : '';
  const idBoxes = n => '<span class="ob-boxes">' + '<i></i>'.repeat(n) + '</span>';
  const line = (label, val, w = '') => '<div class="ob-line ' + w + '"><b>' + label + '</b> <span class="ob-fill">' + esc(val || '') + '</span></div>';
  const studentName = student ? [student.first_name, student.last_name].filter(Boolean).join(' ') : '';
  const bd = student?.birth_date ? String(student.birth_date).split('-').reverse().join('/') : '';
  return '<article class="ob-sheet" id="obSheet" data-model="' + esc(model.id) + '">' +
    '<header class="ob-head">' + FLAG + '<div class="ob-title"><div>RÉPUBLIQUE DÉMOCRATIQUE DU CONGO</div><div>MINISTÈRE DE L’ÉDUCATION NATIONALE</div><div>ET NOUVELLE CITOYENNETÉ</div></div>' + '<img class="ob-seal" src="assets/img/sceau-ministere.png" alt="Sceau du ministère" width="60" height="55"></header>' +
    '<div class="ob-id"><b>N° ID.</b> ' + idBoxes(20) + '</div>' +
    '<section class="ob-ident"><div>' + line('PROVINCE ÉDUCATIONNELLE :', header.province) + line('VILLE :', header.ville) + line('COMMUNE / TER. :', header.commune) + line('ÉCOLE :', school.name || header.ecole) + '<div class="ob-line"><b>CODE :</b> ' + idBoxes(9) + '</div></div>' +
    '<div>' + line('ÉLÈVE :', studentName) + line('SEXE :', student?.sex === 'M' ? 'M' : student?.sex === 'F' ? 'F' : '') + line('NÉ(E) À :', header.lieuNaissance) + line('LE :', bd) + line('CLASSE :', cls?.class_name) + '<div class="ob-line"><b>N° PERM. :</b> ' + idBoxes(13) + '</div></div></section>' +
    '<h2 class="ob-bt">' + esc(model.title.toUpperCase()) + ' — ANNÉE SCOLAIRE ' + esc(year) + '</h2>' +
    '<table class="ob-table"><thead><tr><th rowspan="2" class="ob-name">BRANCHES</th>' + ts.map((t, i) => '<th colspan="' + colsPerTerm + '">' + tl[i] + '</th>').join('') + '<th colspan="2">TOTAL</th></tr><tr>' +
    ts.map(() => '<th>MAX p.</th><th>' + PERIOD_SHORT[0] + '</th><th>' + PERIOD_SHORT[1] + '</th><th>MAX EX.</th><th>PTS</th><th>MAX ' + (model.regime === 'trimestre' ? 'TRIM.' : 'SEM.') + '</th><th>PTS</th>').join('') + '<th>MAX</th><th>PTS</th></tr></thead>' +
    '<tbody>' + body + maxGen + foot + '</tbody></table>' + fb +
    '<section class="ob-decision"><p>- L’élève passe dans la classe supérieure (1)<br>- L’élève double la classe (1)</p><p class="ob-fait">Fait à <span class="ob-fill"></span>, le <span class="ob-fill"></span></p></section>' +
    '<section class="ob-sign"><div>Signature de l’élève</div><div>Sceau de l’école</div><div>Chef d’établissement<br>Noms &amp; signature</div></section>' +
    '<footer class="ob-note">(1) Biffer la mention inutile. NOTE IMPORTANTE : le bulletin est sans valeur s’il est raturé ou surchargé. Modèle ' + esc(model.code) + ' (reproduction des cours et maxima du bulletin officiel ' + '2024-2025).</footer></article>';
}
const PERIOD_SHORT = ['1re P.', '2e P.'];
const FLAG = '<svg class="ob-flag" viewBox="0 0 90 60" role="img" aria-label="Drapeau de la République démocratique du Congo"><rect width="90" height="60" fill="#0085ca"/><polygon points="0,60 0,46 76,0 90,0 90,14 14,60" fill="#f7d618"/><polygon points="0,60 0,51 82,0 90,0 90,9 8,60" fill="#ce1021"/><polygon points="14,4 16.4,10.8 23.6,10.9 17.8,15.2 19.9,22.1 14,18 8.1,22.1 10.2,15.2 4.4,10.9 11.6,10.8" fill="#f7d618"/></svg>';

/** Grille de saisie des notes d'un élève : une ligne par cours, une case par période. */
export function renderGrid({ model, getPoints }) {
  const keys = allKeys(model.regime);
  let h = '<table class="ob-grid"><thead><tr><th scope="col">Cours</th>' + keys.map(k => '<th scope="col">' + esc(PERIOD_LABELS[k]) + '</th>').join('') + '</tr></thead><tbody>';
  model.domains.forEach(d => d.groups.forEach(g => g.branches.forEach((b, bi) => {
    const idx = flatBranches(model).indexOf(b);
    h += '<tr><th scope="row">' + esc(b.name) + '</th>' + keys.map(k => {
      const mx = maxForKey(model, b, k);
      if (!mx) return '<td class="ob-na"></td>';
      const v = getPoints ? getPoints(b, k) : null;
      return '<td><input type="number" inputmode="decimal" min="0" max="' + mx + '" step="0.25" data-b="' + idx + '" data-k="' + k + '" value="' + (v === null || v === undefined ? '' : v) + '" aria-label="' + esc(b.name + ' — ' + PERIOD_LABELS[k] + ' (sur ' + mx + ')') + '" placeholder="/' + mx + '"></td>';
    }).join('') + '</tr>';
  })));
  return h + '</tbody></table>';
}

/** Éditeur de modèle : une ligne par cours (domaine, groupe, nom, max/période, examen, facultatif). */
export function renderModelEditor(model) {
  let h = '<table class="ob-grid ob-editor"><thead><tr><th>Domaine</th><th>Groupe</th><th>Cours</th><th>Max / période</th><th>Max examen</th><th>Facultatif</th><th><span class="sr-only">Retirer</span></th></tr></thead><tbody>';
  model.domains.forEach(d => d.groups.forEach(g => g.branches.forEach(b => {
    h += '<tr data-row><td><input data-f="dom" value="' + esc(d.name || '') + '" aria-label="Domaine"></td><td><input data-f="grp" value="' + esc(g.name || '') + '" aria-label="Groupe"></td><td><input data-f="name" value="' + esc(b.name) + '" aria-label="Nom du cours" required></td>' +
      '<td><input data-f="p" type="number" min="0" step="0.5" value="' + b.p + '" aria-label="Maximum par période"></td><td><input data-f="exam" type="number" min="0" step="0.5" value="' + (b.exam === undefined ? 2 * b.p : b.exam) + '" aria-label="Maximum examen"></td>' +
      '<td><input data-f="opt" type="checkbox"' + (b.optional ? ' checked' : '') + ' aria-label="Cours facultatif"></td><td><button type="button" class="btn danger small" data-remove-row>Retirer</button></td></tr>';
  })));
  return h + '</tbody></table>';
}
/** Reconstruit un modèle à partir des lignes de l'éditeur. */
export function modelFromEditor(base, rows) {
  const domains = [];
  rows.forEach(r => {
    const dn = r.dom || null, gn = r.grp || null;
    let d = domains.find(x => x.name === dn); if (!d) { d = { name: dn, groups: [] }; domains.push(d); }
    let g = d.groups.find(x => x.name === gn); if (!g) { g = { name: gn, branches: [] }; d.groups.push(g); }
    const p = Number(r.p), e = Number(r.exam);
    const b = { name: r.name.trim(), p };
    if (e !== 2 * p) b.exam = e;
    if (r.opt) b.optional = true;
    g.branches.push(b);
  });
  return { ...base, domains, customised: true };
}
