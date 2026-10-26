// A small PowerPoint (.pptx) writer: 16:9 slides with rectangles, text, pictures and videos. Positions are in inches.
import { zip } from './zip.js';

const EMU = 914400;
const e = (n) => Math.round(n * EMU);
const X = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[c])).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '');
const NS = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
const RT = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const MIME = { png: 'image/png', jpeg: 'image/jpeg', jpg: 'image/jpeg', gif: 'image/gif', mp4: 'video/mp4', m4v: 'video/mp4', mov: 'video/quicktime' };
const FONT = 'Arial';

const fillXML = (c) => (c ? `<a:solidFill><a:srgbClr val="${c}"/></a:solidFill>` : '<a:noFill/>');
const lineXML = (l) => (!l ? '<a:ln><a:noFill/></a:ln>' : `<a:ln w="${Math.round((l.w || 1) * 12700)}">${fillXML(l.color)}${l.dash ? '<a:prstDash val="dash"/>' : ''}</a:ln>`);

export function createDeck({ title = 'Presentation', author = 'E11' } = {}) {
  const slides = [];
  const media = [];   // { name, data, ext }
  const addMedia = (data, ext) => { const name = `media${media.length + 1}.${ext}`; media.push({ name, data, ext }); return name; };

  function slide({ bg = 'FFFFFF', name = '' } = {}) {
    const shapes = [], rels = [{ id: 'rId1', type: `${RT}/slideLayout`, target: '../slideLayouts/slideLayout1.xml' }];
    let nid = 2;
    const rel = (type, target, ext) => { const id = `rId${rels.length + 1}`; rels.push({ id, type, target, ext }); return id; };
    const xfrm = (o) => `<a:xfrm><a:off x="${e(o.x)}" y="${e(o.y)}"/><a:ext cx="${Math.max(1, e(o.w))}" cy="${Math.max(1, e(o.h))}"/></a:xfrm>`;
    const runXML = (r, base) => {
      const o = { ...base, ...r };
      const link = o.url ? `<a:hlinkClick r:id="${rel(`${RT}/hyperlink`, o.url, true)}"/>` : '';
      const lang = o.rtl ? 'ar-AE' : 'en-US';
      const rPr = `<a:rPr lang="${lang}" sz="${Math.round((o.size || 14) * 100)}"${o.bold ? ' b="1"' : ''}${o.italic ? ' i="1"' : ''}${o.url ? ' u="sng"' : ''} dirty="0">${fillXML(o.color || '111111')}<a:latin typeface="${FONT}"/><a:cs typeface="${FONT}"/>${link}</a:rPr>`;
      // (a line break inside a paragraph)
      return String(o.t ?? '').split('\n').map((t) => `<a:r>${rPr}<a:t>${X(t)}</a:t></a:r>`).join(`<a:br>${rPr.replace(link, '')}</a:br>`);
    };
    const parasXML = (paras, base = {}) => (paras && paras.length ? paras : [{ runs: [] }]).map((p) => {
      const o = { ...base, ...p };
      const runs = (p.runs || (p.t != null ? [{ t: p.t }] : [])).map((r) => runXML(r, o)).join('');
      return `<a:p><a:pPr algn="${o.align === 'center' ? 'ctr' : o.align === 'right' || o.rtl ? 'r' : 'l'}"${o.rtl ? ' rtl="1"' : ''}><a:lnSpc><a:spcPct val="${Math.round((o.line || 1.15) * 100000)}"/></a:lnSpc><a:spcAft><a:spcPts val="${Math.round((o.after ?? 4) * 100)}"/></a:spcAft></a:pPr>${runs}<a:endParaRPr lang="${o.rtl ? 'ar-AE' : 'en-US'}" sz="${Math.round((o.size || 14) * 100)}" dirty="0"><a:latin typeface="${FONT}"/><a:cs typeface="${FONT}"/></a:endParaRPr></a:p>`;
    }).join('');
    const api = {
      // a rectangle (optionally rounded) with text inside
      box(o) {
        const id = nid++;
        const ins = e(o.inset ?? 0.08);
        shapes.push(`<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="${X(o.name || `Shape ${id}`)}"/><p:cNvSpPr${o.textbox ? ' txBox="1"' : ''}/><p:nvPr/></p:nvSpPr>
<p:spPr>${xfrm(o)}<a:prstGeom prst="${o.radius ? 'roundRect' : 'rect'}"><a:avLst>${o.radius ? `<a:gd name="adj" fmla="val ${Math.round(Math.min(50000, (o.radius / Math.min(o.w, o.h)) * 100000))}"/>` : ''}</a:avLst></a:prstGeom>${fillXML(o.fill)}${lineXML(o.line)}</p:spPr>
<p:txBody><a:bodyPr wrap="square" lIns="${ins}" tIns="${ins}" rIns="${ins}" bIns="${ins}" anchor="${o.anchor === 'middle' ? 'ctr' : o.anchor === 'bottom' ? 'b' : 't'}" rtlCol="0"><a:noAutofit/></a:bodyPr><a:lstStyle/>${parasXML(o.paras, o.style || {})}</p:txBody></p:sp>`);
        return api;
      },
      text(o) { return api.box({ textbox: true, inset: 0, ...o }); },
      // a picture: fit (whole picture inside the box) or cover (fills the box, cropped)
      image(o) {
        const id = nid++;
        const target = addMedia(o.data, o.ext);
        const rid = rel(`${RT}/image`, `../media/${target}`);
        let { x, y, w, h } = o, crop = '';
        const ar = o.iw && o.ih ? o.iw / o.ih : null;
        if (ar && o.fit !== 'cover') { if (ar > w / h) { const nh = w / ar; y += (h - nh) / 2; h = nh; } else { const nw = h * ar; x += (w - nw) / 2; w = nw; } }
        if (ar && o.fit === 'cover') { const box = w / h; if (ar > box) { const cut = (1 - box / ar) / 2; crop = `<a:srcRect l="${Math.round(cut * 100000)}" r="${Math.round(cut * 100000)}"/>`; } else { const cut = (1 - ar / box) / 2; crop = `<a:srcRect t="${Math.round(cut * 100000)}" b="${Math.round(cut * 100000)}"/>`; } }
        shapes.push(`<p:pic><p:nvPicPr><p:cNvPr id="${id}" name="${X(o.name || `Picture ${id}`)}" descr="${X(o.alt || '')}"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="${rid}"/>${crop}<a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>${xfrm({ x, y, w, h })}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>`);
        return api;
      },
      // a video that plays in PowerPoint (the poster picture shows in the PDF)
      video(o) {
        const id = nid++;
        const vname = addMedia(o.data, o.ext);
        const pname = addMedia(o.poster.data, o.poster.ext);
        const rv = rel(`${RT}/video`, `../media/${vname}`);
        const rm = rel('http://schemas.microsoft.com/office/2007/relationships/media', `../media/${vname}`);
        const rp = rel(`${RT}/image`, `../media/${pname}`);
        let { x, y, w, h } = o;
        const ar = o.iw && o.ih ? o.iw / o.ih : null;
        if (ar) { if (ar > w / h) { const nh = w / ar; y += (h - nh) / 2; h = nh; } else { const nw = h * ar; x += (w - nw) / 2; w = nw; } }
        shapes.push(`<p:pic><p:nvPicPr><p:cNvPr id="${id}" name="${X(o.name || `Video ${id}`)}"><a:hlinkClick r:id="" action="ppaction://media"/></p:cNvPr><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr><a:videoFile r:link="${rv}"/><p:extLst><p:ext uri="{DAA4B4D4-6D71-4841-9C94-3DE88004E7FA}"><p14:media xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main" r:embed="${rm}"/></p:ext></p:extLst></p:nvPr></p:nvPicPr><p:blipFill><a:blip r:embed="${rp}"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>${xfrm({ x, y, w, h })}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>`);
        return api;
      },
    };
    slides.push({ bg, name, shapes, rels });
    return api;
  }

  function build() {
    const files = [];
    const add = (name, data, store) => files.push({ name, data, store });
    const exts = new Set(media.map((m) => m.ext));
    add('[Content_Types].xml', `${HEAD}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>${[...exts].map((x) => `<Default Extension="${x}" ContentType="${MIME[x] || 'application/octet-stream'}"/>`).join('')}<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/><Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/><Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/><Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>${slides.map((_, i) => `<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>`).join('')}</Types>`);
    add('_rels/.rels', `${HEAD}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${RT}/officeDocument" Target="ppt/presentation.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="${RT}/extended-properties" Target="docProps/app.xml"/></Relationships>`);
    const now = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
    add('docProps/core.xml', `${HEAD}<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>${X(title)}</dc:title><dc:creator>${X(author)}</dc:creator><cp:lastModifiedBy>${X(author)}</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">${now}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${now}</dcterms:modified></cp:coreProperties>`);
    add('docProps/app.xml', `${HEAD}<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>E11 Console</Application><Slides>${slides.length}</Slides><PresentationFormat>Widescreen</PresentationFormat></Properties>`);
    add('ppt/presentation.xml', `${HEAD}<p:presentation ${NS} saveSubsetFonts="1"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>${slides.map((_, i) => `<p:sldId id="${256 + i}" r:id="rId${i + 10}"/>`).join('')}</p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>`);
    add('ppt/_rels/presentation.xml.rels', `${HEAD}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${RT}/slideMaster" Target="slideMasters/slideMaster1.xml"/><Relationship Id="rId2" Type="${RT}/theme" Target="theme/theme1.xml"/><Relationship Id="rId3" Type="${RT}/presProps" Target="presProps.xml"/><Relationship Id="rId4" Type="${RT}/viewProps" Target="viewProps.xml"/><Relationship Id="rId5" Type="${RT}/tableStyles" Target="tableStyles.xml"/>${slides.map((_, i) => `<Relationship Id="rId${i + 10}" Type="${RT}/slide" Target="slides/slide${i + 1}.xml"/>`).join('')}</Relationships>`);
    add('ppt/presProps.xml', `${HEAD}<p:presentationPr ${NS}/>`);
    add('ppt/viewProps.xml', `${HEAD}<p:viewPr ${NS}><p:normalViewPr><p:restoredLeft sz="15620"/><p:restoredTop sz="94660"/></p:normalViewPr><p:gridSpacing cx="76200" cy="76200"/></p:viewPr>`);
    add('ppt/tableStyles.xml', `${HEAD}<a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>`);
    const emptyTree = '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree>';
    add('ppt/slideMasters/slideMaster1.xml', `${HEAD}<p:sldMaster ${NS}><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>${emptyTree}</p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>`);
    add('ppt/slideMasters/_rels/slideMaster1.xml.rels', `${HEAD}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${RT}/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="${RT}/theme" Target="../theme/theme1.xml"/></Relationships>`);
    add('ppt/slideLayouts/slideLayout1.xml', `${HEAD}<p:sldLayout ${NS} type="blank" preserve="1"><p:cSld name="Blank">${emptyTree}</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>`);
    add('ppt/slideLayouts/_rels/slideLayout1.xml.rels', `${HEAD}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="${RT}/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>`);
    add('ppt/theme/theme1.xml', THEME);
    slides.forEach((s, i) => {
      const tree = emptyTree.replace('</p:spTree>', s.shapes.join('') + '</p:spTree>');
      add(`ppt/slides/slide${i + 1}.xml`, `${HEAD}<p:sld ${NS}><p:cSld${s.name ? ` name="${X(s.name)}"` : ''}><p:bg><p:bgPr>${fillXML(s.bg)}<a:effectLst/></p:bgPr></p:bg>${tree}</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>`);
      add(`ppt/slides/_rels/slide${i + 1}.xml.rels`, `${HEAD}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${s.rels.map((r) => `<Relationship Id="${r.id}" Type="${r.type}" Target="${X(r.target)}"${r.ext ? ' TargetMode="External"' : ''}/>`).join('')}</Relationships>`);
    });
    media.forEach((m) => add(`ppt/media/${m.name}`, m.data, true));
    return zip(files);
  }
  return { slide, build, W: 13.333, H: 7.5 };
}

const THEME = `${HEAD}<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="E11"><a:themeElements><a:clrScheme name="E11"><a:dk1><a:srgbClr val="111111"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="333333"/></a:dk2><a:lt2><a:srgbClr val="F4F4F4"/></a:lt2><a:accent1><a:srgbClr val="7B68EE"/></a:accent1><a:accent2><a:srgbClr val="E0561B"/></a:accent2><a:accent3><a:srgbClr val="3DDC97"/></a:accent3><a:accent4><a:srgbClr val="F2B23E"/></a:accent4><a:accent5><a:srgbClr val="5B9BFF"/></a:accent5><a:accent6><a:srgbClr val="E5484D"/></a:accent6><a:hlink><a:srgbClr val="2A5BB8"/></a:hlink><a:folHlink><a:srgbClr val="6B3FD1"/></a:folHlink></a:clrScheme><a:fontScheme name="E11"><a:majorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface="Arial"/></a:majorFont><a:minorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface="Arial"/></a:minorFont></a:fontScheme><a:fmtScheme name="E11"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>`;
