"""
The games' words for each companion but the cat, in every language: "Catch the
puppy", "Kuchukchani tut", "Поймай щенка". Each language has its own sentence
shapes and the noun forms they need, so the grammar stays right without a form
per sentence per companion. tools/strings.py writes them out as `<key>_<pet>`
strings and the table in ui/games/PetStrings.kt.
"""

PETS = ["puppy", "chick", "canary", "lamb", "owl", "hamster"]
KEYS = ["game_catch", "game_naps", "catch_hint", "boxes_watch", "detail_boxes", "detail_boxes_best", "naps_count",
        "naps_share_text", "boxes_rules", "catch_rules", "laser_rules", "naps_rules"]
FLIES = {"canary", "owl"}


def cap(s):
    return s[:1].upper() + s[1:]


def en(p):
    n = {"puppy": "puppy", "chick": "chick", "canary": "canary", "lamb": "lamb", "owl": "owlet", "hamster": "hamster"}[p]
    pl = {"puppy": "puppies", "chick": "chicks", "canary": "canaries", "lamb": "lambs", "owl": "owlets", "hamster": "hamsters"}[p]
    away = "flies away" if p in FLIES else "jumps away"
    return {
        "game_catch": f"Catch the {n}",
        "game_naps": f"{cap(n)} Naps",
        "catch_hint": f"Tap the {n}",
        "boxes_watch": f"Watch the box with the {n}",
        "detail_boxes": f"Keep your eye on the {n}.",
        "detail_boxes_best": f"Best %d. Keep your eye on the {n}.",
        "naps_count": f"%1$d of %2$d {pl} asleep",
        "naps_share_text": f"{cap(n)} Naps #%1$d · %2$s · %3$s",
        "boxes_rules": f"The {n} hides in a box, and the boxes change places. Keep your eye on it, then tap the box it is in. It gets quicker with every find. Three wrong boxes and the game is over.",
        "catch_rules": f"Tap the {n} before it {away}. Thirty seconds, and it gets quicker with every catch. Five in a row and each catch counts double.",
        "laser_rules": f"Your finger is the dot. When the {n} crouches, it is about to pounce: get out of its way. Every pounce you dodge is a point, and after three in a row each one counts double.",
        "naps_rules": f"Every cushion wants one {n} asleep on it. One {n} to a row, one to a column, and no two touching, not even at a corner. Tap once to rule a cell out, twice for a {n}.",
    }


def uz(p):
    n = {"puppy": "kuchukcha", "chick": "jo'jacha", "canary": "kanareyka", "lamb": "qo'zichoq", "owl": "boyo'g'licha", "hamster": "hamyak"}[p]
    away = "uchib ketmasidan" if p in FLIES else "sakrab ketmasidan"
    return {
        "game_catch": f"{cap(n)}ni tut",
        "game_naps": f"{cap(n)} uyqusi",
        "catch_hint": f"{cap(n)}ni bosing",
        "boxes_watch": f"{cap(n)}li qutini kuzating",
        "detail_boxes": f"{cap(n)}dan ko'z uzmang.",
        "detail_boxes_best": f"Rekord: %d. {cap(n)}dan ko'z uzmang.",
        "naps_count": f"%2$d tadan %1$d ta {n} uxlayapti",
        "naps_share_text": f"{cap(n)} uyqusi #%1$d · %2$s · %3$s",
        "boxes_rules": f"{cap(n)} qutiga yashirinadi, qutilar esa joy almashadi. Ko'zingizni uzmang, keyin u turgan qutini bosing. Har topganingizda tezlashadi. Uch marta adashsangiz, o'yin tugaydi.",
        "catch_rules": f"{cap(n)} {away} uni bosing. O'ttiz soniya, har tutganingizda u tezlashadi. Ketma-ket beshta tutsangiz, har biri ikki baravar hisoblanadi.",
        "laser_rules": f"Barmog'ingiz — lazer nuqtasi. {cap(n)} cho'kkalasa, hozir sakraydi: uning yo'lidan qoching. Har qochilgan sakrash — bir ochko, ketma-ket uchtadan keyin har biri ikki baravar.",
        "naps_rules": f"Har bir yostiqchada bitta {n} uxlashi kerak. Har qatorda bitta, har ustunda bitta, va hech qaysi ikkitasi bir-biriga tegmasin — hatto burchakdan ham. Bir bosish — katakni chiqarib tashlash, ikki bosish — {n}.",
    }


def ru(p):
    # nominative, accusative, genitive, instrumental, genitive plural; feminine?
    nom, acc, gen, ins, gpl, fem = {
        "puppy": ("щенок", "щенка", "щенка", "щенком", "щенят", False),
        "chick": ("цыплёнок", "цыплёнка", "цыплёнка", "цыплёнком", "цыплят", False),
        "canary": ("канарейка", "канарейку", "канарейки", "канарейкой", "канареек", True),
        "lamb": ("ягнёнок", "ягнёнка", "ягнёнка", "ягнёнком", "ягнят", False),
        "owl": ("совёнок", "совёнка", "совёнка", "совёнком", "совят", False),
        "hamster": ("хомяк", "хомяка", "хомяка", "хомяком", "хомяков", False),
    }[p]
    he, him, his = ("она", "ней", "её") if fem else ("он", "ним", "его")
    gone = ("улетела" if fem else "улетел") if p in FLIES else ("отпрыгнула" if fem else "отпрыгнул")
    one = "одна" if fem else "один"
    must = "должна" if fem else "должен"
    by_one, two = ("По одной", "две") if fem else ("По одному", "два")
    return {
        "game_catch": f"Поймай {acc}",
        "game_naps": f"Сон {gpl}",
        "catch_hint": f"Нажмите на {acc}",
        "boxes_watch": f"Следите за коробкой с {ins}",
        "detail_boxes": f"Не спускайте глаз с {gen}.",
        "detail_boxes_best": f"Рекорд: %d. Не спускайте глаз с {gen}.",
        "naps_count": f"Спят %1$d из %2$d {gpl}",
        "naps_share_text": f"Сон {gpl} #%1$d · %2$s · %3$s",
        "boxes_rules": f"{cap(nom)} прячется в коробку, а коробки меняются местами. Следите за {him}, затем нажмите на нужную коробку. С каждой находкой быстрее. Три ошибки — и игра окончена.",
        "catch_rules": f"Нажмите на {acc}, пока {he} не {gone}. Тридцать секунд, и с каждой поимкой {he} быстрее. Пять подряд — и каждая поимка считается вдвойне.",
        "laser_rules": f"Ваш палец — это точка. Когда {nom} припадает к земле, {he} вот-вот прыгнет: уходите с {his} пути. Каждый увернутый прыжок — очко, а после трёх подряд каждый считается вдвойне.",
        "naps_rules": f"На каждой подушке {must} спать {one} {nom}. {by_one} в строке и в столбце, и никакие {two} не соприкасаются, даже углами. Одно касание — исключить клетку, два — {nom}.",
    }


def de(p):
    nom, acc, dat, pnom, pacc, pdat, pl, naps, sleeping, one, one_short, put = {
        "puppy": ("der Welpe", "den Welpen", "dem Welpen", "er", "ihn", "ihm", "Welpen", "Welpenschlaf", "ein schlafender Welpe", "Ein Welpe", "einer", "einen Welpen"),
        "chick": ("das Küken", "das Küken", "dem Küken", "es", "es", "ihm", "Küken", "Kükenschlaf", "ein schlafendes Küken", "Ein Küken", "eins", "ein Küken"),
        "canary": ("der Kanarienvogel", "den Kanarienvogel", "dem Kanarienvogel", "er", "ihn", "ihm", "Kanarienvögel", "Kanarienvogelschlaf", "ein schlafender Kanarienvogel", "Ein Kanarienvogel", "einer", "einen Kanarienvogel"),
        "lamb": ("das Lamm", "das Lamm", "dem Lamm", "es", "es", "ihm", "Lämmer", "Lämmerschlaf", "ein schlafendes Lamm", "Ein Lamm", "eins", "ein Lamm"),
        "owl": ("das Eulchen", "das Eulchen", "dem Eulchen", "es", "es", "ihm", "Eulchen", "Eulchenschlaf", "ein schlafendes Eulchen", "Ein Eulchen", "eins", "ein Eulchen"),
        "hamster": ("der Hamster", "den Hamster", "dem Hamster", "er", "ihn", "ihm", "Hamster", "Hamsterschlaf", "ein schlafender Hamster", "Ein Hamster", "einer", "einen Hamster"),
    }[p]
    away = "wegfliegt" if p in FLIES else "wegspringt"
    return {
        "game_catch": f"Fang {acc}",
        "game_naps": naps,
        "catch_hint": f"Tipp auf {acc}",
        "boxes_watch": f"Achte auf die Box mit {dat}",
        "detail_boxes": f"Behalte {acc} im Auge.",
        "detail_boxes_best": f"Bestwert %d. Behalte {acc} im Auge.",
        "naps_count": f"%1$d von %2$d {pl} schlafen",
        "naps_share_text": f"{naps} Nr. %1$d · %2$s · %3$s",
        "boxes_rules": f"{cap(nom)} versteckt sich in einer Box, und die Boxen tauschen die Plätze. Behalte {pacc} im Auge und tippe dann auf seine Box. Mit jedem Fund wird es schneller. Drei falsche Boxen, und das Spiel ist vorbei.",
        "catch_rules": f"Tipp auf {acc}, bevor {pnom} {away}. Dreißig Sekunden, und mit jedem Fang wird {pnom} schneller. Fünf in Folge, und jeder Fang zählt doppelt.",
        "laser_rules": f"Dein Finger ist der Punkt. Duckt sich {nom}, springt {pnom} gleich: Weich {pdat} aus! Jeder Sprung, dem du ausweichst, ist ein Punkt, und nach dreien in Folge zählt jeder doppelt.",
        "naps_rules": f"Auf jedes Kissen gehört {sleeping}. {one} pro Zeile, {one_short} pro Spalte, und keine zwei berühren sich, auch nicht an einer Ecke. Einmal tippen schließt ein Feld aus, zweimal setzt {put}.",
    }


def es(p):
    n, pl = {"puppy": ("cachorro", "cachorros"), "chick": ("pollito", "pollitos"), "canary": ("canario", "canarios"),
             "lamb": ("corderito", "corderitos"), "owl": ("búho", "búhos"), "hamster": ("hámster", "hámsteres")}[p]
    away = "se vaya volando" if p in FLIES else "salte"
    return {
        "game_catch": f"Atrapa al {n}",
        "game_naps": f"Siesta de {pl}",
        "catch_hint": f"Toca al {n}",
        "boxes_watch": f"Mira la caja del {n}",
        "detail_boxes": f"No le quites el ojo al {n}.",
        "detail_boxes_best": f"Récord %d. No le quites el ojo al {n}.",
        "naps_count": f"%1$d de %2$d {pl} dormidos",
        "naps_share_text": f"Siesta de {pl} n.º %1$d · %2$s · %3$s",
        "boxes_rules": f"El {n} se esconde en una caja y las cajas cambian de sitio. No le quites el ojo y toca la caja donde está. Cada vez que lo encuentras va más rápido. Tres cajas equivocadas y se acaba el juego.",
        "catch_rules": f"Toca al {n} antes de que {away}. Treinta segundos, y va más rápido con cada captura. Cinco seguidas y cada captura vale doble.",
        "laser_rules": f"Tu dedo es el punto. Cuando el {n} se agacha, está a punto de saltar: apártate de su camino. Cada salto que esquivas es un punto, y tras tres seguidos cada uno cuenta doble.",
        "naps_rules": f"Cada cojín quiere un {n} dormido. Un {n} por fila, uno por columna, y ninguno tocándose, ni siquiera en una esquina. Toca una vez para descartar una casilla, dos para poner un {n}.",
    }


def fr(p):
    n, pl, le, du, de_, fem = {
        "puppy": ("chiot", "chiots", "le chiot", "du chiot", "de chiot", False),
        "chick": ("poussin", "poussins", "le poussin", "du poussin", "de poussin", False),
        "canary": ("canari", "canaris", "le canari", "du canari", "de canari", False),
        "lamb": ("agneau", "agneaux", "l’agneau", "de l’agneau", "d’agneau", False),
        "owl": ("chouette", "chouettes", "la chouette", "de la chouette", "de chouette", True),
        "hamster": ("hamster", "hamsters", "le hamster", "du hamster", "de hamster", False),
    }[p]
    il = "elle" if fem else "il"
    qu = "qu’elle" if fem else "qu’il"
    away = "ne s’envole" if p in FLIES else "ne s’échappe"
    a = "une" if fem else "un"
    asleep = "endormie" if fem else "endormi"
    return {
        "game_catch": f"Attrape {le}",
        "game_naps": f"Siestes {de_}",
        "catch_hint": f"Touchez {le}",
        "boxes_watch": f"Regarde la boîte {du}",
        "detail_boxes": f"Garde l’œil sur {le}.",
        "detail_boxes_best": f"Record %d. Garde l’œil sur {le}.",
        "naps_count": f"%1$d {pl} sur %2$d {'endormies' if fem else 'endormis'}",
        "naps_share_text": f"Siestes {de_} nº %1$d · %2$s · %3$s",
        "boxes_rules": f"{cap(le)} se cache dans une boîte, et les boîtes changent de place. Garde l’œil dessus, puis touche la boîte où {il} est. Ça va plus vite à chaque fois. Trois mauvaises boîtes et la partie est finie.",
        "catch_rules": f"Touchez {le} avant {qu} {away}. Trente secondes, et {il} accélère à chaque prise. Cinq d’affilée et chaque prise compte double.",
        "laser_rules": f"Ton doigt est le point. Quand {le} se tapit, {il} va bondir : écarte-toi de son chemin. Chaque bond esquivé vaut un point, et après trois d’affilée, chacun compte double.",
        "naps_rules": f"Chaque coussin attend {a} {n} {asleep}. {cap(a)} {n} par ligne, {a} par colonne, et jamais deux qui se touchent, même par un coin. Touchez une fois pour exclure une case, deux fois pour {a} {n}.",
    }


def it(p):
    n, pl, il, con = {
        "puppy": ("cucciolo", "cuccioli", "il cucciolo", "con il cucciolo"),
        "chick": ("pulcino", "pulcini", "il pulcino", "con il pulcino"),
        "canary": ("canarino", "canarini", "il canarino", "con il canarino"),
        "lamb": ("agnellino", "agnellini", "l’agnellino", "con l’agnellino"),
        "owl": ("gufetto", "gufetti", "il gufetto", "con il gufetto"),
        "hamster": ("criceto", "criceti", "il criceto", "con il criceto"),
    }[p]
    away = "voli via" if p in FLIES else "salti via"
    return {
        "game_catch": f"Acchiappa {il}",
        "game_naps": f"Pisolini di {n}",
        "catch_hint": f"Tocca {il}",
        "boxes_watch": f"Guarda la scatola {con}",
        "detail_boxes": f"Non perdere d’occhio {il}.",
        "detail_boxes_best": f"Record %d. Non perdere d’occhio {il}.",
        "naps_count": f"%1$d {pl} su %2$d addormentati",
        "naps_share_text": f"Pisolini di {n} n. %1$d · %2$s · %3$s",
        "boxes_rules": f"{cap(il)} si nasconde in una scatola e le scatole si scambiano di posto. Non perderlo d’occhio, poi tocca la scatola in cui si trova. Diventa più veloce a ogni scoperta. Tre scatole sbagliate e la partita è finita.",
        "catch_rules": f"Tocca {il} prima che {away}. Trenta secondi, e diventa più veloce a ogni presa. Cinque di fila e ogni presa vale doppio.",
        "laser_rules": f"Il tuo dito è il puntino. Quando {il} si acquatta, sta per balzare: togliti dalla sua strada. Ogni balzo schivato vale un punto, e dopo tre di fila ognuno vale doppio.",
        "naps_rules": f"Ogni cuscino vuole un {n} addormentato. Un {n} per riga, uno per colonna, e mai due che si toccano, nemmeno in diagonale. Tocca una volta per escludere una casella, due per un {n}.",
    }


def pt_br(p):
    n, pl, fem = {"puppy": ("filhote", "filhotes", False), "chick": ("pintinho", "pintinhos", False),
                  "canary": ("canário", "canários", False), "lamb": ("cordeirinho", "cordeirinhos", False),
                  "owl": ("corujinha", "corujinhas", True), "hamster": ("hamster", "hamsters", False)}[p]
    o, no, do, dos, ele, dele, um, nenhum, outro, rapido = (
        ("a", "na", "da", "das", "ela", "dela", "uma", "nenhuma", "na outra", "rápida") if fem else
        ("o", "no", "do", "dos", "ele", "dele", "um", "nenhum", "no outro", "rápido"))
    away = "voe" if p in FLIES else "pule"
    title = " ".join(cap(w) for w in pl.split())
    return {
        "game_catch": f"Pegue {o} {n}",
        "game_naps": f"Soneca {dos} {title}",
        "catch_hint": f"Toque {no} {n}",
        "boxes_watch": f"Olhe a caixa com {o} {n}",
        "detail_boxes": f"Não tire o olho {do} {n}.",
        "detail_boxes_best": f"Recorde %d. Não tire o olho {do} {n}.",
        "naps_count": f"%1$d de %2$d {pl} dormindo",
        "naps_share_text": f"Soneca {dos} {title} nº %1$d · %2$s · %3$s",
        "boxes_rules": f"{cap(o)} {n} se esconde numa caixa, e as caixas trocam de lugar. Não tire o olho {dele} e toque na caixa em que {ele} está. Fica mais rápido a cada acerto. Três caixas erradas e o jogo acaba.",
        "catch_rules": f"Toque {no} {n} antes que {ele} {away}. Trinta segundos, e {ele} fica mais {rapido} a cada captura. Cinco seguidas e cada captura vale o dobro.",
        "laser_rules": f"Seu dedo é o ponto. Quando {o} {n} se agacha, {ele} vai dar o bote: saia do caminho {dele}. Cada bote que você desvia vale um ponto, e depois de três seguidos cada um vale o dobro.",
        "naps_rules": f"Cada almofada quer {um} {n} dormindo. {cap(um)} {n} por linha, {um} por coluna, e {nenhum} encostando {outro}, nem pela quina. Toque uma vez para descartar uma casa, duas para pôr {um} {n}.",
    }


def tr(p):
    n, acc, dat, abl, gen, title = {
        "puppy": ("köpek yavrusu", "köpek yavrusunu", "köpek yavrusuna", "köpek yavrusundan", "köpek yavrusunun", "Köpek Yavrusu"),
        "chick": ("civciv", "civcivi", "civcive", "civcivden", "civcivin", "Civciv"),
        "canary": ("kanarya", "kanaryayı", "kanaryaya", "kanaryadan", "kanaryanın", "Kanarya"),
        "lamb": ("kuzu", "kuzuyu", "kuzuya", "kuzudan", "kuzunun", "Kuzu"),
        "owl": ("baykuş yavrusu", "baykuş yavrusunu", "baykuş yavrusuna", "baykuş yavrusundan", "baykuş yavrusunun", "Baykuş Yavrusu"),
        "hamster": ("hamster", "hamsteri", "hamstere", "hamsterden", "hamsterin", "Hamster"),
    }[p]
    return {
        "game_catch": f"{cap(acc)} yakala",
        "game_naps": f"{title} Uykusu",
        "catch_hint": f"{cap(dat)} dokun",
        "boxes_watch": f"{cap(gen)} olduğu kutuya bak",
        "detail_boxes": f"Gözünü {abl} ayırma.",
        "detail_boxes_best": f"En iyi %d. Gözünü {abl} ayırma.",
        "naps_count": f"%1$d/%2$d {n} uyuyor",
        "naps_share_text": f"{title} Uykusu #%1$d · %2$s · %3$s",
        "boxes_rules": f"{cap(n)} bir kutuya saklanır ve kutular yer değiştirir. Gözünü ondan ayırma, sonra {gen} olduğu kutuya dokun. Her bulduğunda hızlanır. Üç yanlış kutu ve oyun biter.",
        "catch_rules": f"{cap(n)} kaçmadan ona dokun. Otuz saniye, ve her yakalamada hızlanır. Arka arkaya beş tane, sonra her yakalama iki sayılır.",
        "laser_rules": f"Parmağın noktadır. {cap(n)} çömeldiğinde atılmak üzeredir: yolundan çekil. Kaçtığın her atılış bir puan, arka arkaya üçten sonra her biri iki sayılır.",
        "naps_rules": f"Her minder üstünde uyuyan bir {n} ister. Her satırda bir {n}, her sütunda bir {n}; köşeden bile olsa iki {n} birbirine değmez. Bir dokunuş hücreyi eler, iki dokunuş {n} koyar.",
    }


def ja(p):
    n = {"puppy": "子イヌ", "chick": "ひよこ", "canary": "カナリア", "lamb": "子ヒツジ", "owl": "子フクロウ", "hamster": "ハムスター"}[p]
    bird = p in ("chick", "canary", "owl")
    counter, one = ("羽", "一羽") if bird else ("匹", "一匹")
    away = "飛んで" if p in FLIES else "跳んで"
    return {
        "game_catch": f"{n}をつかまえろ",
        "game_naps": f"{n}のおひるね",
        "catch_hint": f"{n}をタップ",
        "boxes_watch": f"{n}の入った箱を見て",
        "detail_boxes": f"{n}から目を離さないで。",
        "detail_boxes_best": f"ベスト %d。{n}から目を離さないで。",
        "naps_count": f"%1$d/%2$d{counter}がおやすみ中",
        "naps_share_text": f"{n}のおひるね No.%1$d · %2$s · %3$s",
        "boxes_rules": f"{n}が箱に隠れて、箱が入れ替わります。目を離さずに、{n}の入った箱をタップ。見つけるたびに速くなります。3回まちがえるとゲームオーバー。",
        "catch_rules": f"{n}が{away}逃げる前にタップ。30秒間、つかまえるたびに速くなります。5回連続でつかまえると、1回が2倍に。",
        "laser_rules": f"指がレーザーの点。{n}が身をかがめたら飛びかかる合図。さっとよけよう。かわすたびに1点、3回連続のあとは1回が2倍に。",
        "naps_rules": f"どのクッションにも{n}を{one}寝かせましょう。各行に{one}、各列に{one}。{n}同士は角も含めて隣り合ってはいけません。1回タップでマスを除外、2回で{n}を置きます。",
    }


def ko(p):
    n = {"puppy": "강아지", "chick": "병아리", "canary": "카나리아", "lamb": "아기 양", "owl": "아기 부엉이", "hamster": "햄스터"}[p]
    batchim = (ord(n[-1]) - 0xAC00) % 28 != 0
    obj, subj = ("을", "이") if batchim else ("를", "가")
    return {
        "game_catch": f"{n}{obj} 잡아라",
        "game_naps": f"{n} 낮잠",
        "catch_hint": f"{n}{obj} 탭하세요",
        "boxes_watch": f"{n}{subj} 든 상자를 보세요",
        "detail_boxes": f"{n}에게서 눈을 떼지 마세요.",
        "detail_boxes_best": f"최고 %d. {n}에게서 눈을 떼지 마세요.",
        "naps_count": f"{n} %1$d/%2$d마리 잠듦",
        "naps_share_text": f"{n} 낮잠 %1$d번 · %2$s · %3$s",
        "boxes_rules": f"{n}{subj} 상자에 숨고 상자들이 자리를 바꿔요. 눈을 떼지 말고 {n}{subj} 든 상자를 탭하세요. 찾을 때마다 빨라져요. 세 번 틀리면 게임이 끝나요.",
        "catch_rules": f"{n}{subj} 도망가기 전에 탭하세요. 30초 동안, 잡을 때마다 더 빨라져요. 5번 연속 잡으면 한 번에 두 배.",
        "laser_rules": f"손가락이 레이저 점이에요. {n}{subj} 몸을 낮추면 곧 덮쳐요. 재빨리 피하세요. 피할 때마다 1점, 세 번 연속 뒤로는 한 번이 2점이에요.",
        "naps_rules": f"쿠션마다 잠든 {n} 한 마리가 필요해요. 행마다 한 마리, 열마다 한 마리, 그리고 모서리까지 포함해 서로 닿으면 안 돼요. 한 번 탭하면 칸을 제외하고, 두 번 탭하면 {n}{obj} 놓아요.",
    }


def zh(p, traditional):
    n = ({"puppy": "小狗", "chick": "小雞", "canary": "金絲雀", "lamb": "小羊", "owl": "小貓頭鷹", "hamster": "倉鼠"} if traditional else
         {"puppy": "小狗", "chick": "小鸡", "canary": "金丝雀", "lamb": "小羊", "owl": "小猫头鹰", "hamster": "仓鼠"})[p]
    if traditional:
        away = "飛走" if p in FLIES else "跳走"
        return {
            "game_catch": f"抓住{n}",
            "game_naps": f"{n}午睡",
            "catch_hint": f"點{n}",
            "boxes_watch": f"看好{n}的盒子",
            "detail_boxes": f"盯緊{n}。",
            "detail_boxes_best": f"最佳 %d。盯緊{n}。",
            "naps_count": f"%1$d/%2$d 隻{n}睡著了",
            "naps_share_text": f"{n}午睡 第 %1$d 期 · %2$s · %3$s",
            "boxes_rules": f"{n}躲進一個盒子，盒子們交換位置。盯緊牠，然後點牠所在的盒子。每找到一次就更快。猜錯三次遊戲結束。",
            "catch_rules": f"在{n}{away}前點牠。三十秒，每抓到一次牠就更快。連續五次後，每次抓到都算雙倍。",
            "laser_rules": f"你的手指就是光點。{n}伏低身子，就是要撲了：快閃開。每躲開一次撲擊得一分，連續三次後每次都算雙倍。",
            "naps_rules": f"每個靠墊上都要睡一隻{n}。每列一隻、每欄一隻，任何兩隻{n}都不能相鄰，斜角也不行。點一下排除格子，點兩下放{n}。",
        }
    away = "飞走" if p in FLIES else "跳走"
    return {
        "game_catch": f"抓住{n}",
        "game_naps": f"{n}午睡",
        "catch_hint": f"点{n}",
        "boxes_watch": f"看好{n}的盒子",
        "detail_boxes": f"盯紧{n}。",
        "detail_boxes_best": f"最佳 %d。盯紧{n}。",
        "naps_count": f"%1$d/%2$d 只{n}睡着了",
        "naps_share_text": f"{n}午睡 第 %1$d 期 · %2$s · %3$s",
        "boxes_rules": f"{n}躲进一个盒子，盒子们交换位置。盯紧它，然后点它所在的盒子。每找到一次就更快。猜错三次游戏结束。",
        "catch_rules": f"在{n}{away}前点它。三十秒，每抓到一次它就更快。连续五次后，每次抓到都算双倍。",
        "laser_rules": f"你的手指就是光点。{n}伏低身子，就是要扑了：快闪开。每躲开一次扑击得一分，连续三次后每次都算双倍。",
        "naps_rules": f"每个靠垫上都要睡一只{n}。每行一只、每列一只，任何两只{n}都不能相邻，斜角也不行。点一下排除格子，点两下放{n}。",
    }


LANGS = {
    "en": en, "uz": uz, "ru": ru, "de": de, "es": es, "fr": fr, "it": it, "pt-BR": pt_br, "tr": tr,
    "ja": ja, "ko": ko, "zh-Hans": lambda p: zh(p, False), "zh-Hant": lambda p: zh(p, True),
}


def strings(lang):
    """Every `<key>_<pet>` string in `lang`."""
    out = {}
    for p in PETS:
        words = LANGS[lang](p)
        assert set(words) == set(KEYS), (lang, p, set(KEYS) ^ set(words))
        for k in KEYS:
            out[f"{k}_{p}"] = words[k]
    return out


def kotlin():
    """The table from each game string to its companions' versions."""
    rows = []
    for k in KEYS:
        entries = ", ".join(f"Pet.{'OWL' if p == 'owl' else p.upper()} to R.string.{k}_{p}" for p in PETS)
        rows.append(f"        R.string.{k} to mapOf({entries}),")
    return "\n".join([
        "// Generated by tools/strings.py from tools/pets.py. Edit there.",
        "package uz.ata.dawnwick.ui.games",
        "",
        "import uz.ata.dawnwick.R",
        "import uz.ata.dawnwick.companion.Pet",
        "",
        "/** The games' words that name the cat, and each companion's version of them. */",
        "object PetStrings {",
        "    private val table: Map<Int, Map<Pet, Int>> = mapOf(",
        *rows,
        "    )",
        "",
        "    /** `id` as `pet` would have it: the cat's own words when there is no other version. */",
        "    fun of(id: Int, pet: Pet): Int = table[id]?.get(pet) ?: id",
        "}",
        "",
    ])
