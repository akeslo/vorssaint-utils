// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardImageOptimizerStrings {
    let title: String
    let hubDescription: String
    let enable: String
    let caption: String
    let formatLabel: String
    let formatKeep: String
    let formatJPEG: String
    let formatCaption: String
    let quality: String
    let maxDimension: String
    let maxDimensionOff: String
    let halveRetina: String
    let halveRetinaCaption: String
    let includeFiles: String
    let includeFilesCaption: String

    static func localized(_ language: AppLanguage) -> ClipboardImageOptimizerStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension FeatureStrings {
    static func clipboardImageOptimizer(_ language: AppLanguage) -> ClipboardImageOptimizerStrings {
        ClipboardImageOptimizerStrings.localized(language)
    }
}

extension ClipboardImageOptimizerStrings {
    static let enUS = ClipboardImageOptimizerStrings(
        title: "Clipboard image optimizer",
        hubDescription: "Copied screenshots and images get smaller",
        enable: "Shrink copied images",
        caption: "With Keep, copied PNG and TIFF images are re-encoded without quality loss when that saves space. JPEG and resizing are lossy. Images copied with text, links or formatting are left alone.",
        formatLabel: "Format",
        formatKeep: "Keep (lossless)",
        formatJPEG: "JPEG",
        formatCaption: "JPEG is much smaller but blurs text. Images with transparency stay PNG.",
        quality: "JPEG quality",
        maxDimension: "Maximum size",
        maxDimensionOff: "Off",
        halveRetina: "Scale Retina images to 1x",
        halveRetinaCaption: "Halves the width and height, like a screenshot taken on a standard display.",
        includeFiles: "Also optimize copied image files",
        includeFilesCaption: "A copied PNG, JPEG or TIFF file is replaced by its optimized image, so pasting in Finder no longer copies the file."
    )

    static let ptBR = ClipboardImageOptimizerStrings(
        title: "Otimizador de imagens copiadas",
        hubDescription: "Capturas e imagens copiadas ficam menores",
        enable: "Reduzir imagens copiadas",
        caption: "Com Manter, imagens PNG e TIFF copiadas são recodificadas sem perda de qualidade quando isso economiza espaço. JPEG e redimensionamento perdem qualidade. Imagens copiadas com texto, links ou formatação não são alteradas.",
        formatLabel: "Formato",
        formatKeep: "Manter (sem perdas)",
        formatJPEG: "JPEG",
        formatCaption: "JPEG fica bem menor, mas borra textos. Imagens com transparência continuam em PNG.",
        quality: "Qualidade do JPEG",
        maxDimension: "Tamanho máximo",
        maxDimensionOff: "Desativado",
        halveRetina: "Reduzir imagens Retina para 1x",
        halveRetinaCaption: "Divide a largura e a altura pela metade, como uma captura feita em uma tela comum.",
        includeFiles: "Otimizar também arquivos de imagem copiados",
        includeFilesCaption: "Um arquivo PNG, JPEG ou TIFF copiado é substituído pela imagem otimizada, então colar no Finder não copia mais o arquivo."
    )

    static let tr = ClipboardImageOptimizerStrings(
        title: "Pano görüntü iyileştirici",
        hubDescription: "Kopyalanan ekran görüntüleri ve resimler küçülür",
        enable: "Kopyalanan resimleri küçült",
        caption: "Koru seçiliyken kopyalanan PNG ve TIFF resimler, yer kazandırdığında kalite kaybı olmadan yeniden kodlanır. JPEG ve yeniden boyutlandırma kalite kaybettirir. Metin, bağlantı veya biçimlendirmeyle kopyalanan resimlere dokunulmaz.",
        formatLabel: "Biçim",
        formatKeep: "Koru (kayıpsız)",
        formatJPEG: "JPEG",
        formatCaption: "JPEG çok daha küçüktür ama metni bulanıklaştırır. Saydamlığı olan resimler PNG olarak kalır.",
        quality: "JPEG kalitesi",
        maxDimension: "En büyük boyut",
        maxDimensionOff: "Kapalı",
        halveRetina: "Retina resimlerini 1x boyutuna indir",
        halveRetinaCaption: "Genişliği ve yüksekliği yarıya indirir, standart bir ekranda alınmış bir ekran görüntüsü gibi.",
        includeFiles: "Kopyalanan resim dosyalarını da iyileştir",
        includeFilesCaption: "Kopyalanan bir PNG, JPEG veya TIFF dosyası iyileştirilmiş resmiyle değiştirilir; Finder’da yapıştırmak artık dosyayı kopyalamaz."
    )

    static let ru = ClipboardImageOptimizerStrings(
        title: "Оптимизатор изображений в буфере",
        hubDescription: "Скопированные снимки экрана и изображения становятся меньше",
        enable: "Сжимать скопированные изображения",
        caption: "В режиме «Сохранять» скопированные изображения PNG и TIFF перекодируются без потери качества, если это экономит место. JPEG и уменьшение размера снижают качество. Изображения, скопированные вместе с текстом, ссылками или форматированием, не изменяются.",
        formatLabel: "Формат",
        formatKeep: "Сохранять (без потерь)",
        formatJPEG: "JPEG",
        formatCaption: "JPEG намного меньше, но размывает текст. Изображения с прозрачностью остаются в PNG.",
        quality: "Качество JPEG",
        maxDimension: "Максимальный размер",
        maxDimensionOff: "Выкл.",
        halveRetina: "Уменьшать изображения Retina до 1x",
        halveRetinaCaption: "Уменьшает ширину и высоту вдвое, как у снимка экрана на обычном дисплее.",
        includeFiles: "Оптимизировать и скопированные файлы изображений",
        includeFilesCaption: "Скопированный файл PNG, JPEG или TIFF заменяется оптимизированным изображением, поэтому вставка в Finder больше не копирует сам файл."
    )

    static let es = ClipboardImageOptimizerStrings(
        title: "Optimizador de imágenes copiadas",
        hubDescription: "Las capturas e imágenes copiadas ocupan menos",
        enable: "Reducir las imágenes copiadas",
        caption: "Con Mantener, las imágenes PNG y TIFF copiadas se recodifican sin pérdida de calidad cuando así ocupan menos. JPEG y el cambio de tamaño pierden calidad. Las imágenes copiadas junto con texto, enlaces o formato no se tocan.",
        formatLabel: "Formato",
        formatKeep: "Mantener (sin pérdida)",
        formatJPEG: "JPEG",
        formatCaption: "JPEG ocupa mucho menos, pero difumina el texto. Las imágenes con transparencia siguen en PNG.",
        quality: "Calidad JPEG",
        maxDimension: "Tamaño máximo",
        maxDimensionOff: "No",
        halveRetina: "Reducir las imágenes Retina a 1x",
        halveRetinaCaption: "Reduce a la mitad el ancho y el alto, como una captura hecha en una pantalla estándar.",
        includeFiles: "Optimizar también los archivos de imagen copiados",
        includeFilesCaption: "Un archivo PNG, JPEG o TIFF copiado se sustituye por su imagen optimizada, así que al pegar en el Finder ya no se copia el archivo."
    )

    static let sk = ClipboardImageOptimizerStrings(
        title: "Optimalizátor obrázkov v schránke",
        hubDescription: "Skopírované snímky obrazovky a obrázky budú menšie",
        enable: "Zmenšovať skopírované obrázky",
        caption: "Pri voľbe Zachovať sa skopírované obrázky PNG a TIFF znova zakódujú bez straty kvality, ak to ušetrí miesto. JPEG a zmena veľkosti kvalitu znižujú. Obrázky skopírované spolu s textom, odkazmi alebo formátovaním zostanú nezmenené.",
        formatLabel: "Formát",
        formatKeep: "Zachovať (bezstratovo)",
        formatJPEG: "JPEG",
        formatCaption: "JPEG je oveľa menší, ale rozmazáva text. Obrázky s priehľadnosťou zostanú v PNG.",
        quality: "Kvalita JPEG",
        maxDimension: "Maximálna veľkosť",
        maxDimensionOff: "Vypnuté",
        halveRetina: "Zmenšiť obrázky Retina na 1x",
        halveRetinaCaption: "Zmenší šírku aj výšku na polovicu, ako pri snímke z bežného displeja.",
        includeFiles: "Optimalizovať aj skopírované obrázkové súbory",
        includeFilesCaption: "Skopírovaný súbor PNG, JPEG alebo TIFF sa nahradí optimalizovaným obrázkom, takže vloženie vo Finderi už súbor neskopíruje."
    )

    static let de = ClipboardImageOptimizerStrings(
        title: "Bildoptimierung für die Zwischenablage",
        hubDescription: "Kopierte Bildschirmfotos und Bilder werden kleiner",
        enable: "Kopierte Bilder verkleinern",
        caption: "Mit „Beibehalten“ werden kopierte PNG- und TIFF-Bilder verlustfrei neu kodiert, wenn das Platz spart. JPEG und Verkleinern sind verlustbehaftet. Bilder, die zusammen mit Text, Links oder Formatierung kopiert wurden, bleiben unverändert.",
        formatLabel: "Format",
        formatKeep: "Beibehalten (verlustfrei)",
        formatJPEG: "JPEG",
        formatCaption: "JPEG ist viel kleiner, macht Text aber unscharf. Bilder mit Transparenz bleiben PNG.",
        quality: "JPEG-Qualität",
        maxDimension: "Maximale Größe",
        maxDimensionOff: "Aus",
        halveRetina: "Retina-Bilder auf 1x verkleinern",
        halveRetinaCaption: "Halbiert Breite und Höhe, wie bei einem Bildschirmfoto auf einem normalen Display.",
        includeFiles: "Auch kopierte Bilddateien optimieren",
        includeFilesCaption: "Eine kopierte PNG-, JPEG- oder TIFF-Datei wird durch ihr optimiertes Bild ersetzt, daher kopiert das Einsetzen im Finder die Datei nicht mehr."
    )

    static let fr = ClipboardImageOptimizerStrings(
        title: "Optimiseur d’images copiées",
        hubDescription: "Les captures et images copiées deviennent plus légères",
        enable: "Alléger les images copiées",
        caption: "Avec Conserver, les images PNG et TIFF copiées sont réencodées sans perte de qualité quand cela réduit leur taille. Le JPEG et le redimensionnement réduisent la qualité. Les images copiées avec du texte, des liens ou une mise en forme ne sont pas modifiées.",
        formatLabel: "Format",
        formatKeep: "Conserver (sans perte)",
        formatJPEG: "JPEG",
        formatCaption: "Le JPEG est bien plus léger mais rend le texte flou. Les images avec transparence restent en PNG.",
        quality: "Qualité JPEG",
        maxDimension: "Taille maximale",
        maxDimensionOff: "Désactivée",
        halveRetina: "Réduire les images Retina en 1x",
        halveRetinaCaption: "Divise la largeur et la hauteur par deux, comme une capture faite sur un écran standard.",
        includeFiles: "Optimiser aussi les fichiers image copiés",
        includeFilesCaption: "Un fichier PNG, JPEG ou TIFF copié est remplacé par son image optimisée. Coller dans le Finder ne copie donc plus le fichier."
    )

    static let it = ClipboardImageOptimizerStrings(
        title: "Ottimizzatore immagini copiate",
        hubDescription: "Screenshot e immagini copiate diventano più leggeri",
        enable: "Riduci le immagini copiate",
        caption: "Con Mantieni, le immagini PNG e TIFF copiate vengono ricodificate senza perdita di qualità quando si risparmia spazio. JPEG e ridimensionamento riducono la qualità. Le immagini copiate insieme a testo, link o formattazione restano intatte.",
        formatLabel: "Formato",
        formatKeep: "Mantieni (senza perdita)",
        formatJPEG: "JPEG",
        formatCaption: "Il JPEG è molto più leggero ma sfoca il testo. Le immagini con trasparenza restano PNG.",
        quality: "Qualità JPEG",
        maxDimension: "Dimensione massima",
        maxDimensionOff: "No",
        halveRetina: "Riduci le immagini Retina a 1x",
        halveRetinaCaption: "Dimezza larghezza e altezza, come uno screenshot fatto su un monitor standard.",
        includeFiles: "Ottimizza anche i file immagine copiati",
        includeFilesCaption: "Un file PNG, JPEG o TIFF copiato viene sostituito dalla sua immagine ottimizzata, quindi incollando nel Finder il file non viene più copiato."
    )

    static let ja = ClipboardImageOptimizerStrings(
        title: "クリップボード画像の最適化",
        hubDescription: "コピーしたスクリーンショットや画像を小さく",
        enable: "コピーした画像を縮小",
        caption: "「維持」では、コピーした PNG と TIFF の画像は、容量が減る場合に画質を落とさずに再エンコードされます。JPEG とサイズ変更では画質が落ちます。テキスト、リンク、書式と一緒にコピーした画像は変更しません。",
        formatLabel: "フォーマット",
        formatKeep: "維持（可逆）",
        formatJPEG: "JPEG",
        formatCaption: "JPEG はかなり小さくなりますが、文字がぼやけます。透明部分のある画像は PNG のままです。",
        quality: "JPEG の画質",
        maxDimension: "最大サイズ",
        maxDimensionOff: "オフ",
        halveRetina: "Retina 画像を 1x に縮小",
        halveRetinaCaption: "標準ディスプレイで撮ったスクリーンショットのように、幅と高さを半分にします。",
        includeFiles: "コピーした画像ファイルも最適化",
        includeFilesCaption: "コピーした PNG、JPEG、TIFF ファイルは最適化した画像に置き換わるため、Finder でペーストしてもファイルはコピーされなくなります。"
    )

    static let ko = ClipboardImageOptimizerStrings(
        title: "클립보드 이미지 최적화",
        hubDescription: "복사한 스크린샷과 이미지를 더 작게",
        enable: "복사한 이미지 줄이기",
        caption: "유지를 선택하면 복사한 PNG 및 TIFF 이미지는 용량이 줄어드는 경우 화질 손실 없이 다시 인코딩됩니다. JPEG와 크기 조절은 화질이 떨어집니다. 텍스트, 링크 또는 서식과 함께 복사한 이미지는 그대로 둡니다.",
        formatLabel: "포맷",
        formatKeep: "유지(무손실)",
        formatJPEG: "JPEG",
        formatCaption: "JPEG는 훨씬 작지만 글자가 흐려집니다. 투명한 부분이 있는 이미지는 PNG로 유지됩니다.",
        quality: "JPEG 품질",
        maxDimension: "최대 크기",
        maxDimensionOff: "끔",
        halveRetina: "Retina 이미지를 1x로 줄이기",
        halveRetinaCaption: "일반 디스플레이에서 찍은 스크린샷처럼 너비와 높이를 절반으로 줄입니다.",
        includeFiles: "복사한 이미지 파일도 최적화",
        includeFilesCaption: "복사한 PNG, JPEG 또는 TIFF 파일이 최적화된 이미지로 바뀌므로 Finder에서 붙여넣어도 파일이 더 이상 복사되지 않습니다."
    )

    static let zhHans = ClipboardImageOptimizerStrings(
        title: "剪贴板图像优化",
        hubDescription: "拷贝的截屏和图像变得更小",
        enable: "缩小拷贝的图像",
        caption: "选择“保持”时，拷贝的 PNG 和 TIFF 图像在能节省空间时会无损重新编码。JPEG 和缩放会损失画质。与文本、链接或格式一起拷贝的图像保持不变。",
        formatLabel: "格式",
        formatKeep: "保持（无损）",
        formatJPEG: "JPEG",
        formatCaption: "JPEG 小得多，但会让文字变模糊。带透明度的图像仍为 PNG。",
        quality: "JPEG 质量",
        maxDimension: "最大尺寸",
        maxDimensionOff: "关闭",
        halveRetina: "将 Retina 图像缩小为 1x",
        halveRetinaCaption: "将宽度和高度减半，就像在标准显示器上截取的屏幕快照。",
        includeFiles: "同时优化拷贝的图像文件",
        includeFilesCaption: "拷贝的 PNG、JPEG 或 TIFF 文件会替换为优化后的图像，因此在访达中粘贴将不再拷贝该文件。"
    )

    static let zhTW = ClipboardImageOptimizerStrings(
        title: "剪貼板影像最佳化",
        hubDescription: "拷貝的截圖和影像會變得更小",
        enable: "縮小拷貝的影像",
        caption: "選擇「保持」時，揀「保持」時，拷貝的 PNG 和 TIFF 影像在能節省空間時會無損重新編碼。JPEG 同縮放會損失畫質。JPEG 和縮放會損失畫質。與文字、連結或格式一起拷貝的影像保持不變。",
        formatLabel: "格式",
        formatKeep: "保持（無損）",
        formatJPEG: "JPEG",
        formatCaption: "JPEG 小得多，但會讓文字變模糊。含透明度的影像仍為 PNG。",
        quality: "JPEG 品質",
        maxDimension: "最大尺寸",
        maxDimensionOff: "關閉",
        halveRetina: "將 Retina 影像縮小為 1x",
        halveRetinaCaption: "將寬度和高度減半，就像在標準顯示器上擷取的截圖。",
        includeFiles: "同時最佳化拷貝的影像檔案",
        includeFilesCaption: "拷貝的 PNG、JPEG 或 TIFF 檔案會替換為最佳化後的影像，因此在 Finder 中貼上將不再拷貝該檔案。"
    )

    static let zhHK = ClipboardImageOptimizerStrings(
        title: "剪貼板影像優化",
        hubDescription: "拷貝的截圖和影像會變得更細",
        enable: "縮細拷貝的影像",
        caption: "拷貝的 PNG 和 TIFF 影像在能節省空間時會無損重新編碼。與文字、連結或格式一起拷貝的影像保持不變。",
        formatLabel: "格式",
        formatKeep: "保持（無損）",
        formatJPEG: "JPEG",
        formatCaption: "JPEG 細得多，但會令文字變模糊。含透明度的影像仍為 PNG。",
        quality: "JPEG 質素",
        maxDimension: "最大尺寸",
        maxDimensionOff: "關閉",
        halveRetina: "將 Retina 影像縮細為 1x",
        halveRetinaCaption: "將闊度和高度減半，就好似喺標準顯示器上擷取的截圖。",
        includeFiles: "同時優化拷貝的影像檔案",
        includeFilesCaption: "拷貝的 PNG、JPEG 或 TIFF 檔案會換成優化後的影像，因此喺 Finder 貼上將不再拷貝該檔案。"
    )

    static let uk = ClipboardImageOptimizerStrings(
        title: "Оптимізатор зображень у буфері",
        hubDescription: "Скопійовані знімки екрана й зображення стають меншими",
        enable: "Стискати скопійовані зображення",
        caption: "У режимі «Зберігати» скопійовані зображення PNG і TIFF перекодовуються без втрати якості, якщо це заощаджує місце. JPEG і зменшення розміру знижують якість. Зображення, скопійовані разом із текстом, посиланнями чи форматуванням, не змінюються.",
        formatLabel: "Формат",
        formatKeep: "Зберігати (без втрат)",
        formatJPEG: "JPEG",
        formatCaption: "JPEG значно менший, але розмиває текст. Зображення з прозорістю залишаються в PNG.",
        quality: "Якість JPEG",
        maxDimension: "Максимальний розмір",
        maxDimensionOff: "Вимк.",
        halveRetina: "Зменшувати зображення Retina до 1x",
        halveRetinaCaption: "Зменшує ширину й висоту вдвічі, як у знімка екрана на звичайному дисплеї.",
        includeFiles: "Оптимізувати й скопійовані файли зображень",
        includeFilesCaption: "Скопійований файл PNG, JPEG або TIFF замінюється оптимізованим зображенням, тому вставлення у Finder більше не копіює сам файл."
    )
}
