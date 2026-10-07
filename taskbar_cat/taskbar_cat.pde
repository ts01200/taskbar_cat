// =============================================================
//  タスクバーの上を歩く猫            Processing 4 / Windows

//  ・猫を左クリックで押さえたまま動かす … つかんで持ち上げられます
//    (はなすと、下のタスクバーにストンと落ちます)
//  ・猫を右クリック … 終了    (PDEの ■ ボタンでもOK)
// =============================================================

import java.awt.AlphaComposite;
import java.awt.Color;
import java.awt.Graphics;
import java.awt.Graphics2D;
import java.awt.GraphicsEnvironment;
import java.awt.Rectangle;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import javax.swing.JPanel;
import javax.swing.JWindow;

// ---------- 設定(ここを変えて遊べます) ----------
final float SCALE = 0.7;       // 猫の大きさ (1.0で標準、1.5で1.5倍)
final float SPEED = 1.5;       // 歩く速さ (px/フレーム)

final int FUR   = 0xFFF2B35E;  // 毛のいろ(オレンジ)
final int FUR_D = 0xFFD98A3D;  // 濃い毛(しま模様・奥の足)
final int CREAM = 0xFFFFF1D6;  // 白っぽい部分(おなか・足先・口まわり)
final int PINK  = 0xFFFF9AA8;  // 鼻・耳の中
final int INK   = 0xFF3A2A25;  // 目・口
// ------------------------------------------------

final int WALK = 0, SIT = 1, SLEEP = 2, HELD = 3, FALL = 4;
final float UW = 170, UH = 160;   // 猫を描くエリアの大きさ(SCALE=1のときのpx)
final float HANG_H = 99;                   // つかまれた猫の「つかまれた場所」から足先までの長さ
final float PIVOT_Y = UH - 2 - HANG_H;     // エリアの中での「つかまれた場所」の高さ

JWindow win;             // 背景が透明なウィンドウ(猫の本体)
CatPanel panel;
PGraphics pg;            // 猫を描く透明なキャンバス
int winW, winH, groundY;
float ui = 1;            // 画面の拡大率(Windowsの「拡大/縮小」設定)。くっきり描くために使う
float x, y, minX, maxX;  // 猫(ウィンドウ)の左上の座標
int dir = 1;             // 1=右向き  -1=左向き
int state = WALK;
float stateTimer = 200;  // 今の行動の残りフレーム数
float phase = 0;         // 歩きアニメーションの位相

// ---- つかむ / 落ちる ----
volatile boolean holding = false;     // 左ボタンを押している間 true
volatile boolean grabEvent = false;   // 押された瞬間だけ true
volatile int curX, curY;              // マウスの画面上の位置
float vx, vy;                         // 落ちているときの速さ
float holdVX, holdVY;                 // つかんでいる間の動き(はなした勢いに使う)
float grabOffX, grabDY, liftY;        // つかんだ位置のずれ(横はだんだん0に) と、持ち上げた高さ
float swing, swingV;                  // ぶらんぶらんの角度と角速度
float surprise;                       // びっくりしている残りフレーム数
float flailPhase;                     // 手足をばたばたさせる位相
float squash, squashV;                // 着地でぷにっとつぶれる量


void setup() {
  size(100, 100);                 // Processing本体の窓(すぐ隠します)
  surface.setVisible(false);
  frameRate(30);

  // 画面の拡大率に合わせて、猫を高解像度で描く
  ui = (float) GraphicsEnvironment.getLocalGraphicsEnvironment()
         .getDefaultScreenDevice().getDefaultConfiguration()
         .getDefaultTransform().getScaleX();

  winW = round(UW * SCALE);
  winH = round(UH * SCALE);
  pg = createGraphics(round(winW * ui), round(winH * ui));
  pg.smooth(4);

  // タスクバーを除いた「作業領域」の下端 = タスクバーの上端
  Rectangle wa = GraphicsEnvironment.getLocalGraphicsEnvironment().getMaximumWindowBounds();
  groundY = wa.y + wa.height;
  minX = wa.x - 20 * SCALE;
  maxX = wa.x + wa.width - winW + 20 * SCALE;
  x = (minX + maxX) / 2;
  y = groundY - winH;

  panel = new CatPanel();
  panel.setCursor(new java.awt.Cursor(java.awt.Cursor.HAND_CURSOR));   // 猫の上では「手」のカーソル
  java.awt.event.MouseAdapter mouse = new java.awt.event.MouseAdapter() {
    public void mousePressed(java.awt.event.MouseEvent e) {
      if (e.getButton() == java.awt.event.MouseEvent.BUTTON3) {
        win.dispose();            // 右クリックで終了
        exit();
      } else if (e.getButton() == java.awt.event.MouseEvent.BUTTON1) {
        curX = e.getXOnScreen();  // 左ボタンでつかむ
        curY = e.getYOnScreen();
        holding = true;
        grabEvent = true;
      }
    }
    public void mouseDragged(java.awt.event.MouseEvent e) {
      if (holding) {
        curX = e.getXOnScreen();
        curY = e.getYOnScreen();
      }
    }
    public void mouseReleased(java.awt.event.MouseEvent e) {
      if (e.getButton() == java.awt.event.MouseEvent.BUTTON1) holding = false;   // はなす
    }
  };
  panel.addMouseListener(mouse);
  panel.addMouseMotionListener(mouse);

  win = new JWindow();
  win.setAlwaysOnTop(true);                    // いつも手前に表示
  win.setFocusableWindowState(false);          // 他のアプリの操作をじゃましない
  try {
    win.setBackground(new Color(0, 0, 0, 0));  // ★背景を透明にする
  } catch (Exception e) {
    println("この環境では透明ウィンドウを使えませんでした: " + e);
  }
  win.setContentPane(panel);
  win.setSize(winW, winH);
  win.setLocation(round(x), round(y));
  win.setVisible(true);
}

void draw() {
  updateCat();
  panel.setImage(renderCat());
  win.setLocation(round(x), round(y));
}


// ---------------------------------------------------------------
//  猫の行動(歩く → 座る → 寝る … をランダムにくり返す)
// ---------------------------------------------------------------
void updateCat() {
  if (grabEvent) {                       // つかまれた!
    grabEvent = false;
    startHold();
  }
  if (state == HELD && !holding) endHold();   // はなされた!

  if (state == HELD) {
    updateHeld();
  } else if (state == FALL) {
    updateFall();
  } else {
    if (state == WALK) {
      x += dir * SPEED;
      phase += 0.17 * SPEED / SCALE;     // 歩く速さに足の動きを合わせる
      if (x < minX) { x = minX; dir = 1; }    // 画面のはしで折り返す
      if (x > maxX) { x = maxX; dir = -1; }
    }
    y = groundY - winH;                  // タスクバーの上に立つ
    stateTimer--;
    if (stateTimer <= 0) nextState();
  }

  // 着地のぷにっ(ばねでゆれて元にもどる)
  squashV += -0.22 * squash - 0.16 * squashV;
  squash += squashV;
}

// ---------------------------------------------------------------
//  つかむ → 持ち上げる → はなす → 落ちる
//  (つかんでいる間と落ちている間は、動きをなめらかにするため 60fps)
// ---------------------------------------------------------------
void startHold() {
  state = HELD;
  swing = 0;  swingV = 0;
  holdVX = 0;  holdVY = 0;
  vx = 0;  vy = 0;
  grabOffX = curX - (x + UW / 2 * SCALE);   // クリックした場所と猫の中心の横のずれ
  grabDY = curY - y;                        // クリックした高さはそのまま保つ(いきなり上下に動かさない)
  liftY = 0;
  surprise = 30;                         // 持ち上げられてびっくり
  frameRate(60);
}

void updateHeld() {
  // マウスを追いかける。横は猫がだんだんマウスの真下にくる。縦は、つかんだ高さのまま
  // (ひょいっと少しだけ持ち上がる)
  grabOffX *= 0.92;
  liftY += (18 - liftY) * 0.25;
  float tx = curX - grabOffX - UW / 2 * SCALE;
  float ty = curY - grabDY - liftY;
  float px = x, py = y;
  x += (tx - x) * 0.4;
  y += (ty - y) * 0.4;
  float mvx = x - px, mvy = y - py;      // 1フレームで動いた量
  holdVX = lerp(holdVX, mvx, 0.4);
  holdVY = lerp(holdVY, mvy, 0.4);

  // ぶらんぶらん: 横に動かすと体が遅れてついてきて、止めるとゆれもどる
  float target = constrain(mvx * 0.09, -0.5, 0.5);
  swingV += -0.022 * (swing - target) - 0.045 * swingV;
  swing = constrain(swing + swingV, -0.5, 0.5);

  // 速く動かすと「わーっ」と手足をばたばた
  if (sqrt(mvx * mvx + mvy * mvy) > 4 || abs(swingV) > 0.03) surprise = 25;
  else if (surprise > 0) surprise--;
  flailPhase += 0.5;
}

void endHold() {
  state = FALL;
  vx = constrain(holdVX, -16, 16);       // はなした勢いのまま飛んでいく
  vy = constrain(holdVY, -24, 28);
}

void updateFall() {
  vy = min(vy + 0.8, 30);                // 重力
  x += vx;
  y += vy;
  vx *= 0.97;
  x += (constrain(x, minX, maxX) - x) * 0.25;   // 画面の外へは行かせない
  swing *= 0.85;                         // 空中で体勢を立て直す
  swingV *= 0.85;
  surprise = 25;
  flailPhase += 0.6;

  float gy = groundY - winH;
  if (y >= gy) {                         // 着地!
    y = gy;
    squash = constrain(vy * 0.012, 0.06, 0.3);
    squashV = 0;
    vx = 0;  vy = 0;
    frameRate(30);
    setState(SIT, random(60, 140));      // ちょっと座って、ひと息
  }
}

void setState(int s, float frames) {
  state = s;
  stateTimer = frames;
}

void nextState() {
  float r = random(1);
  if (state == WALK) {
    if (r < 0.50)      setState(SIT, random(120, 270));
    else if (r < 0.70) setState(SLEEP, random(300, 600));
    else {
      if (random(1) < 0.5) dir = -dir;
      setState(WALK, random(150, 300));
    }
  } else if (state == SIT) {
    if (r < 0.25) setState(SLEEP, random(300, 600));
    else {
      if (random(1) < 0.5) dir = -dir;
      setState(WALK, random(150, 360));
    }
  } else {                             // 寝ていた → ちょっと座ってから動く
    setState(SIT, 90);
  }
}


// ---------------------------------------------------------------
//  描画(猫を透明なキャンバスに描いて、ウィンドウに渡す)
// ---------------------------------------------------------------
BufferedImage renderCat() {
  pg.beginDraw();
  pg.background(0, 0);                      // まず全部を透明にする
  pg.pushMatrix();
  pg.scale(SCALE * ui);

  if (state == HELD || state == FALL) {
    pg.translate(UW / 2, PIVOT_Y);          // 原点 = つかまれている場所
    pg.rotate(swing);                       // ぶらんぶらん
    if (dir < 0) pg.scale(-1, 1);           // 左向きは左右反転
    drawHang(pg, surprise > 0 ? 4 : 1);     // 4=びっくり 1=だらーん(目を閉じる)
  } else {
    pg.translate(UW / 2, UH - 2);           // 原点 = 猫の足元の中心
    pg.scale(1 + squash * 0.5, 1 - squash); // 着地でぷにっ
    pg.pushMatrix();
    if (dir < 0) pg.scale(-1, 1);           // 左向きは左右反転
    int eye = 0;                            // 0=ぱっちり 1=まばたき
    if (frameCount % 140 > 133) eye = 1;
    if (state == WALK) drawWalk(pg, eye);
    else if (state == SIT) drawSit(pg, eye);
    else drawSleep(pg);
    pg.popMatrix();
    drawEffects(pg);                        // Zzz (反転させない)
  }

  pg.popMatrix();
  pg.endDraw();
  return toImage(pg);
}

// ---- 歩いている猫(右向き) ----
void drawWalk(PGraphics g, int eye) {
  float bob = -abs(sin(phase)) * 2;               // 体の上下
  float tw = sin(frameCount * 0.15) * 7;          // しっぽのゆれ

  // しっぽ
  g.noFill();
  g.stroke(FUR);
  g.strokeWeight(9);
  g.strokeCap(ROUND);
  g.bezier(-34, -38 + bob, -54, -34, -58 + tw, -62, -48 + tw * 1.4, -78);
  g.noStroke();
  g.fill(FUR_D);
  g.ellipse(-48 + tw * 1.4, -78, 9, 9);

  // 奥の足(濃い色)
  leg(g, 26, phase + PI, FUR_D);
  leg(g, -14, phase, FUR_D);

  // 体と頭
  g.pushMatrix();
  g.translate(0, bob);
  g.noStroke();
  g.fill(FUR);
  g.ellipse(-4, -36, 70, 40);
  g.fill(CREAM);
  g.ellipse(-4, -22, 44, 10);
  g.stroke(FUR_D);
  g.strokeWeight(4);
  g.line(-26, -48, -24, -41);
  g.line(-16, -52, -15, -44);
  g.line(-6, -53, -5, -45);
  drawHead(g, 34, -56, 0, 4, eye);
  g.popMatrix();

  // 手前の足
  leg(g, 18, phase, FUR);
  leg(g, -24, phase + PI, FUR);
}

// 足1本ぶん(hx=付け根のX, ph=足の位相)
void leg(PGraphics g, float hx, float ph, int col) {
  float px = hx + sin(ph) * 9;                 // 前後にふる
  float py = -4 - max(0, cos(ph)) * 5;         // 前に出すときは持ち上げる
  g.stroke(col);
  g.strokeWeight(9);
  g.strokeCap(ROUND);
  g.line(hx, -26, px, py);
  g.noStroke();
  g.fill(CREAM);                               // 白い靴下
  g.ellipse(px + 1, py + 0.5, 11, 8);
}

// ---- 座っている猫(右向き) ----
void drawSit(PGraphics g, int eye) {
  float tw = sin(frameCount * 0.10) * 5;       // しっぽのゆれ
  float br = sin(frameCount * 0.08) * 0.8;     // 呼吸

  // しっぽ
  g.noFill();
  g.stroke(FUR);
  g.strokeWeight(9);
  g.strokeCap(ROUND);
  g.bezier(-30, -12, -56, -8, -62, -30 + tw, -50 + tw, -44);
  g.noStroke();
  g.fill(FUR_D);
  g.ellipse(-50 + tw, -44, 9, 9);

  // おしり・後ろ足
  g.fill(FUR);
  g.ellipse(-8, -22, 52, 42);
  g.ellipse(2, -5, 28, 10);
  g.fill(CREAM);
  g.ellipse(11, -4.5, 12, 8);
  g.stroke(FUR_D);
  g.strokeWeight(4);
  g.line(-30, -28, -22, -25);
  g.line(-29, -18, -21, -16);

  // 胴体・胸
  g.noStroke();
  g.fill(FUR);
  g.ellipse(12, -44 + br, 34, 56);
  g.fill(CREAM);
  g.ellipse(18, -47 + br, 16, 22);

  // 前足
  g.strokeCap(ROUND);
  g.strokeWeight(9);
  g.stroke(FUR_D);
  g.line(25, -36, 25, -4);
  g.stroke(FUR);
  g.line(16, -36, 16, -4);
  g.noStroke();
  g.fill(CREAM);
  g.ellipse(26, -3.5, 12, 7);
  g.ellipse(17, -3.5, 12, 7);

  drawHead(g, 16, -76 + br, 0, 4, eye);
}

// ---- 寝ている猫(右向き) ----
void drawSleep(PGraphics g) {
  float br = sin(frameCount * 0.07) * 1.2;     // 呼吸

  // 丸まった体
  g.noStroke();
  g.fill(FUR);
  g.ellipse(-4, -19 - br, 96, 38 + br * 2);
  g.stroke(FUR_D);
  g.strokeWeight(4);
  g.strokeCap(ROUND);
  g.line(-32, -30, -30, -23);
  g.line(-20, -33, -19, -25);
  g.line(-8, -34 - br, -7, -26);

  // しっぽ(体の前をぐるっと)
  g.noFill();
  g.strokeWeight(8);
  g.bezier(-50, -14, -44, -2, 10, -2, 42, -9);

  // 頭(前足にのせる)
  drawHead(g, 32, -23, 0.12, 3, 2);
  g.noStroke();
  g.fill(CREAM);
  g.ellipse(30, -3.5, 16, 8);
  g.ellipse(44, -3.5, 16, 8);
}

// ---- つかまれた猫(右向き) ----
//  原点 = 首のうしろ(つかまれている場所)。足先は原点の HANG_H 下。
void drawHang(PGraphics g, int eye) {
  float fl = constrain(surprise / 20.0, 0, 1);       // 0=だらーん  1=じたばた
  float s1 = sin(flailPhase) * fl;
  float s2 = sin(flailPhase + PI) * fl;
  float tOff = constrain(swingV * 120, -14, 14)      // しっぽは体より少し遅れてゆれる
             + sin(flailPhase * 0.4) * (2 + 6 * fl);

  g.pushMatrix();
  g.translate(10, -10);                              // 首のうしろが原点にくるようにずらす

  // しっぽ(だらんと下がる)
  g.noFill();
  g.stroke(FUR);
  g.strokeWeight(9);
  g.strokeCap(ROUND);
  g.bezier(-9, 78, -30 + tOff * 0.4, 80, -38 + tOff, 98, -28 + tOff, 106);
  g.noStroke();
  g.fill(FUR_D);
  g.ellipse(-28 + tOff, 105.5, 9, 9);

  // 奥の後ろ足
  hangLeg(g, 5, 76, 6 + s2 * 7, 103 - max(0, s2) * 8, FUR_D);

  // 体(たてにのびる)・おしり・しま模様
  g.noStroke();
  g.fill(FUR);
  g.ellipse(2, 46, 36, 70);
  g.ellipse(0, 68, 40, 38);
  g.stroke(FUR_D);
  g.strokeWeight(4);
  g.strokeCap(ROUND);
  g.line(-10, 38, -5, 40);
  g.line(-12, 50, -7, 51);
  g.line(-14, 63, -9, 63);

  // 手前の後ろ足
  hangLeg(g, -6, 76, -5 + s1 * 7, 104 - max(0, s1) * 8, FUR);

  // 肩(首と体をつなぐ)・胸の白いところ
  g.noStroke();
  g.fill(FUR);
  g.ellipse(3, 18, 40, 40);
  g.fill(CREAM);
  g.ellipse(14, 44, 12, 18);

  // 前足(胸の前でぶらん)
  hangLeg(g, 17, 32, 21 + s2 * 6, 60 - max(0, s2) * 8, FUR_D);
  hangLeg(g, 9, 34, 12 + s1 * 6, 62 - max(0, s1) * 8, FUR);

  drawHead(g, 12, 24, 0.12, 4, eye);
  g.popMatrix();
}

// ぶらさがった足1本ぶん((hx,hy)=付け根, (px,py)=足先)
void hangLeg(PGraphics g, float hx, float hy, float px, float py, int col) {
  g.stroke(col);
  g.strokeWeight(9);
  g.strokeCap(ROUND);
  g.line(hx, hy, px, py);
  g.noStroke();
  g.fill(CREAM);                               // 白い靴下
  g.ellipse(px + 1, py + 1, 11, 8);
}

// ---- 猫の顔(中心 cx,cy) ----
//  rot=かたむき  look=顔のパーツを進行方向へずらす量
//  eye: 0=ぱっちり 1=まばたき 2=ねてる 3=うれしい 4=びっくり
void drawHead(PGraphics g, float cx, float cy, float rot, float look, int eye) {
  g.pushMatrix();
  g.translate(cx, cy);
  g.rotate(rot);

  // 耳
  g.noStroke();
  g.fill(FUR);
  g.triangle(-19, -10, -3, -19.5, -18, -36);
  g.triangle(19, -10, 3, -19.5, 18, -36);
  g.fill(PINK);
  g.triangle(-16, -15, -8, -20.5, -16, -29.5);
  g.triangle(16, -15, 8, -20.5, 16, -29.5);

  // 顔とおでこのしま
  g.fill(FUR);
  g.ellipse(0, 0, 46, 40);
  g.stroke(FUR_D);
  g.strokeWeight(2.5);
  g.strokeCap(ROUND);
  g.line(0, -19, 0, -12);
  g.line(-6, -18.5, -5, -13);
  g.line(6, -18.5, 5, -13);

  g.translate(look, 0);                        // ここから先は顔のパーツ

  // 口まわり・ほっぺ
  g.noStroke();
  g.fill(CREAM);
  g.ellipse(0, 7, 22, 14);
  g.fill(255, 154, 168, 90);
  g.ellipse(-15, 6, 8, 5);
  g.ellipse(15, 6, 8, 5);

  // 目
  for (int s = -1; s <= 1; s += 2) {
    float ex = s * 9;
    float ey = -2;
    if (eye == 0) {
      g.noStroke();
      g.fill(INK);
      g.ellipse(ex, ey, 6, 8);
      g.fill(255);
      g.ellipse(ex + 1, ey - 2, 2.4, 2.4);     // 目のハイライト
    } else if (eye == 4) {                      // びっくり: 大きな白目と小さな黒目
      g.stroke(INK);
      g.strokeWeight(1.4);
      g.fill(255);
      g.ellipse(ex, ey, 9, 10);
      g.noStroke();
      g.fill(INK);
      g.ellipse(ex + 0.6, ey + 0.8, 3.6, 4.2);
    } else {
      g.noFill();
      g.stroke(INK);
      g.strokeWeight(1.8);
      g.strokeCap(ROUND);
      if (eye == 1) g.line(ex - 3.5, ey, ex + 3.5, ey);         // まばたき
      else if (eye == 2) g.arc(ex, ey - 1, 8, 6, 0, PI);        // ねてる ◡
      else g.arc(ex, ey + 2, 8, 7, PI, TWO_PI);                 // うれしい ◠
    }
  }

  // 鼻と口
  g.noStroke();
  g.fill(PINK);
  g.triangle(-2.6, 3, 2.6, 3, 0, 6.2);
  if (eye == 4) {                               // びっくり: 口をあける
    g.fill(INK);
    g.ellipse(0, 9.8, 4.4, 5.4);
  } else {
    g.noFill();
    g.stroke(INK);
    g.strokeWeight(1.3);
    g.line(0, 6.2, 0, 8.5);
    g.arc(-2.8, 8.5, 5.6, 4.5, 0, PI);
    g.arc(2.8, 8.5, 5.6, 4.5, 0, PI);
  }

  // ひげ
  g.stroke(INK, 120);
  g.strokeWeight(1);
  g.line(-12, 5, -27, 2);
  g.line(-12, 8, -27, 9);
  g.line(12, 5, 27, 2);
  g.line(12, 8, 27, 9);

  g.popMatrix();
}

// ---- Zzz ----
void drawEffects(PGraphics g) {
  if (state != SLEEP) return;
  g.strokeCap(ROUND);
  for (int i = 0; i < 3; i++) {
    float age = (frameCount * 0.6 + i * 20) % 60;
    float zx = dir * (46 + age * 0.45);
    float zy = -52 - age * 0.9;
    float zs = 3.5 + age * 0.1;
    g.noFill();
    g.stroke(110, 140, 220, 255 - age * 4);
    g.strokeWeight(2);
    g.line(zx - zs, zy - zs, zx + zs, zy - zs);
    g.line(zx + zs, zy - zs, zx - zs, zy + zs);
    g.line(zx - zs, zy + zs, zx + zs, zy + zs);
  }
}


// ---------------------------------------------------------------
//  PGraphics → 透明つきの画像(BufferedImage)に変換
// ---------------------------------------------------------------
BufferedImage toImage(PGraphics g) {
  g.loadPixels();
  BufferedImage bi = new BufferedImage(g.width, g.height, BufferedImage.TYPE_INT_ARGB);
  bi.setRGB(0, 0, g.width, g.height, g.pixels, 0, g.width);
  return bi;
}

// ---------------------------------------------------------------
//  透明ウィンドウの中身(受け取った画像をそのまま表示するだけ)
// ---------------------------------------------------------------
class CatPanel extends JPanel {
  volatile BufferedImage img;

  CatPanel() {
    setOpaque(false);
  }

  void setImage(BufferedImage bi) {
    img = bi;
    repaint();
  }

  @Override
  protected void paintComponent(Graphics g) {
    Graphics2D g2 = (Graphics2D) g.create();
    g2.setComposite(AlphaComposite.Clear);          // 前のコマを消す
    g2.fillRect(0, 0, getWidth(), getHeight());
    g2.setComposite(AlphaComposite.SrcOver);
    g2.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                        RenderingHints.VALUE_INTERPOLATION_BILINEAR);
    BufferedImage bi = img;
    if (bi != null) g2.drawImage(bi, 0, 0, getWidth(), getHeight(), null);
    g2.dispose();
  }
}
