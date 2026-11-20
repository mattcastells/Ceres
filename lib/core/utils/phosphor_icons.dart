import 'package:flutter/widgets.dart';

/// Íconos Phosphor (MIT, ver `assets/fonts/Phosphor-LICENSE.txt`), con la
/// misma forma de uso que tenía `phosphor_flutter`: `PhosphorIcons.star()` o
/// `PhosphorIcons.star(PhosphorIconsStyle.fill)`.
///
/// El paquete quedó sin mantenimiento y desde Flutter 3.50 no compila: hereda
/// de [IconData], que ya no se puede extender. Acá están solo los íconos que
/// usa la app; para sumar uno, copiar su código de https://phosphoricons.com
/// en las dos clases privadas de abajo.
///
/// Cada variante es una constante: el tree shaking de la fuente de íconos
/// solo ve los `IconData` constantes.
enum PhosphorIconsStyle { regular, fill }

abstract final class PhosphorIcons {
  static IconData aperture([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.aperture : _Regular.aperture;
  static IconData arrowCounterClockwise([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.arrowCounterClockwise
      : _Regular.arrowCounterClockwise;
  static IconData arrowDown([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.arrowDown : _Regular.arrowDown;
  static IconData arrowUp([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.arrowUp : _Regular.arrowUp;
  static IconData arrowsClockwise([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.arrowsClockwise
      : _Regular.arrowsClockwise;
  static IconData arrowsOutSimple([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.arrowsOutSimple
      : _Regular.arrowsOutSimple;
  static IconData barbell([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.barbell : _Regular.barbell;
  static IconData barcode([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.barcode : _Regular.barcode;
  static IconData bed([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.bed : _Regular.bed;
  static IconData beerBottle([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.beerBottle : _Regular.beerBottle;
  static IconData beerStein([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.beerStein : _Regular.beerStein;
  static IconData bell([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.bell : _Regular.bell;
  static IconData boat([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.boat : _Regular.boat;
  static IconData bookOpenText([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.bookOpenText
      : _Regular.bookOpenText;
  static IconData bowlFood([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.bowlFood : _Regular.bowlFood;
  static IconData boxingGlove([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.boxingGlove
      : _Regular.boxingGlove;
  static IconData brandy([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.brandy : _Regular.brandy;
  static IconData calendarBlank([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.calendarBlank
      : _Regular.calendarBlank;
  static IconData camera([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.camera : _Regular.camera;
  static IconData caretDown([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.caretDown : _Regular.caretDown;
  static IconData caretLeft([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.caretLeft : _Regular.caretLeft;
  static IconData caretRight([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.caretRight : _Regular.caretRight;
  static IconData caretUp([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.caretUp : _Regular.caretUp;
  static IconData champagne([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.champagne : _Regular.champagne;
  static IconData chartLine([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.chartLine : _Regular.chartLine;
  static IconData chatCircleText([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.chatCircleText
      : _Regular.chatCircleText;
  static IconData chatText([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.chatText : _Regular.chatText;
  static IconData check([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.check : _Regular.check;
  static IconData checkCircle([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.checkCircle
      : _Regular.checkCircle;
  static IconData circle([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.circle : _Regular.circle;
  static IconData clock([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.clock : _Regular.clock;
  static IconData clockCounterClockwise([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.clockCounterClockwise
      : _Regular.clockCounterClockwise;
  static IconData cloudArrowDown([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.cloudArrowDown
      : _Regular.cloudArrowDown;
  static IconData cloudArrowUp([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.cloudArrowUp
      : _Regular.cloudArrowUp;
  static IconData cloudCheck([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.cloudCheck : _Regular.cloudCheck;
  static IconData cloudSlash([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.cloudSlash : _Regular.cloudSlash;
  static IconData coffee([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.coffee : _Regular.coffee;
  static IconData cookie([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.cookie : _Regular.cookie;
  static IconData cookingPot([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.cookingPot : _Regular.cookingPot;
  static IconData copySimple([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.copySimple : _Regular.copySimple;
  static IconData couch([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.couch : _Regular.couch;
  static IconData dotsThree([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.dotsThree : _Regular.dotsThree;
  static IconData dotsThreeCircle([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.dotsThreeCircle
      : _Regular.dotsThreeCircle;
  static IconData downloadSimple([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.downloadSimple
      : _Regular.downloadSimple;
  static IconData drop([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.drop : _Regular.drop;
  static IconData eye([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.eye : _Regular.eye;
  static IconData eyeSlash([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.eyeSlash : _Regular.eyeSlash;
  static IconData filePdf([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.filePdf : _Regular.filePdf;
  static IconData flag([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.flag : _Regular.flag;
  static IconData footprints([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.footprints : _Regular.footprints;
  static IconData forkKnife([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.forkKnife : _Regular.forkKnife;
  static IconData gear([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.gear : _Regular.gear;
  static IconData heartbeat([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.heartbeat : _Regular.heartbeat;
  static IconData image([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.image : _Regular.image;
  static IconData imageBroken([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.imageBroken
      : _Regular.imageBroken;
  static IconData images([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.images : _Regular.images;
  static IconData info([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.info : _Regular.info;
  static IconData lightbulb([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.lightbulb : _Regular.lightbulb;
  static IconData magnifyingGlass([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.magnifyingGlass
      : _Regular.magnifyingGlass;
  static IconData martini([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.martini : _Regular.martini;
  static IconData microphone([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.microphone : _Regular.microphone;
  static IconData minus([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.minus : _Regular.minus;
  static IconData moon([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.moon : _Regular.moon;
  static IconData mountains([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.mountains : _Regular.mountains;
  static IconData musicNotes([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.musicNotes : _Regular.musicNotes;
  static IconData palette([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.palette : _Regular.palette;
  static IconData path([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.path : _Regular.path;
  static IconData pencilSimple([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.pencilSimple
      : _Regular.pencilSimple;
  static IconData personSimpleBike([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.personSimpleBike
      : _Regular.personSimpleBike;
  static IconData personSimpleRun([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.personSimpleRun
      : _Regular.personSimpleRun;
  static IconData personSimpleSwim([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.personSimpleSwim
      : _Regular.personSimpleSwim;
  static IconData personSimpleTaiChi([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.personSimpleTaiChi
      : _Regular.personSimpleTaiChi;
  static IconData personSimpleWalk([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.personSimpleWalk
      : _Regular.personSimpleWalk;
  static IconData plant([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.plant : _Regular.plant;
  static IconData play([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.play : _Regular.play;
  static IconData plus([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.plus : _Regular.plus;
  static IconData plusCircle([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.plusCircle : _Regular.plusCircle;
  static IconData pushPin([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.pushPin : _Regular.pushPin;
  static IconData radioButton([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.radioButton
      : _Regular.radioButton;
  static IconData ruler([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.ruler : _Regular.ruler;
  static IconData scales([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.scales : _Regular.scales;
  static IconData shareNetwork([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.shareNetwork
      : _Regular.shareNetwork;
  static IconData shieldCheck([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.shieldCheck
      : _Regular.shieldCheck;
  static IconData signOut([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.signOut : _Regular.signOut;
  static IconData sliders([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.sliders : _Regular.sliders;
  static IconData slidersHorizontal([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.slidersHorizontal
      : _Regular.slidersHorizontal;
  static IconData soccerBall([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) =>
      style == PhosphorIconsStyle.fill ? _Fill.soccerBall : _Regular.soccerBall;
  static IconData sparkle([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.sparkle : _Regular.sparkle;
  static IconData stairs([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.stairs : _Regular.stairs;
  static IconData star([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.star : _Regular.star;
  static IconData stethoscope([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.stethoscope
      : _Regular.stethoscope;
  static IconData target([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.target : _Regular.target;
  static IconData thermometer([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.thermometer
      : _Regular.thermometer;
  static IconData timer([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.timer : _Regular.timer;
  static IconData trash([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.trash : _Regular.trash;
  static IconData user([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.user : _Regular.user;
  static IconData userPlus([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.userPlus : _Regular.userPlus;
  static IconData users([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.users : _Regular.users;
  static IconData warning([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.warning : _Regular.warning;
  static IconData warningCircle([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill
      ? _Fill.warningCircle
      : _Regular.warningCircle;
  static IconData wind([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.wind : _Regular.wind;
  static IconData wine([
    PhosphorIconsStyle style = PhosphorIconsStyle.regular,
  ]) => style == PhosphorIconsStyle.fill ? _Fill.wine : _Regular.wine;
  static IconData x([PhosphorIconsStyle style = PhosphorIconsStyle.regular]) =>
      style == PhosphorIconsStyle.fill ? _Fill.x : _Regular.x;
}

abstract final class _Regular {
  static const aperture = IconData(
    0xe00a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const arrowCounterClockwise = IconData(
    0xe038,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const arrowDown = IconData(
    0xe03e,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const arrowUp = IconData(
    0xe08e,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const arrowsClockwise = IconData(
    0xe094,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const arrowsOutSimple = IconData(
    0xe0a6,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const barbell = IconData(
    0xe0b6,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const barcode = IconData(
    0xe0b8,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const bed = IconData(
    0xe0cc,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const beerBottle = IconData(
    0xe7b0,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const beerStein = IconData(
    0xeb62,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const bell = IconData(
    0xe0ce,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const boat = IconData(
    0xe786,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const bookOpenText = IconData(
    0xe8f2,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const bowlFood = IconData(
    0xeaa4,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const boxingGlove = IconData(
    0xea36,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const brandy = IconData(
    0xe6b4,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const calendarBlank = IconData(
    0xe10a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const camera = IconData(
    0xe10e,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const caretDown = IconData(
    0xe136,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const caretLeft = IconData(
    0xe138,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const caretRight = IconData(
    0xe13a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const caretUp = IconData(
    0xe13c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const champagne = IconData(
    0xeaca,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const chartLine = IconData(
    0xe154,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const chatCircleText = IconData(
    0xe16e,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const chatText = IconData(
    0xe17a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const check = IconData(
    0xe182,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const checkCircle = IconData(
    0xe184,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const circle = IconData(
    0xe18a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const clock = IconData(
    0xe19a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const clockCounterClockwise = IconData(
    0xe1a0,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const cloudArrowDown = IconData(
    0xe1ac,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const cloudArrowUp = IconData(
    0xe1ae,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const cloudCheck = IconData(
    0xe1b0,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const cloudSlash = IconData(
    0xe1b6,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const coffee = IconData(
    0xe1c2,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const cookie = IconData(
    0xe6ca,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const cookingPot = IconData(
    0xe764,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const copySimple = IconData(
    0xe1cc,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const couch = IconData(
    0xe7f6,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const dotsThree = IconData(
    0xe1fe,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const dotsThreeCircle = IconData(
    0xe200,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const downloadSimple = IconData(
    0xe20c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const drop = IconData(
    0xe210,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const eye = IconData(
    0xe220,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const eyeSlash = IconData(
    0xe224,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const filePdf = IconData(
    0xe702,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const flag = IconData(
    0xe244,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const footprints = IconData(
    0xea88,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const forkKnife = IconData(
    0xe262,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const gear = IconData(
    0xe270,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const heartbeat = IconData(
    0xe2ac,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const image = IconData(
    0xe2ca,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const imageBroken = IconData(
    0xe7a8,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const images = IconData(
    0xe836,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const info = IconData(
    0xe2ce,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const lightbulb = IconData(
    0xe2dc,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const magnifyingGlass = IconData(
    0xe30c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const martini = IconData(
    0xe31c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const microphone = IconData(
    0xe326,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const minus = IconData(
    0xe32a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const moon = IconData(
    0xe330,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const mountains = IconData(
    0xe7ae,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const musicNotes = IconData(
    0xe340,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const palette = IconData(
    0xe6c8,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const path = IconData(
    0xe39c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const pencilSimple = IconData(
    0xe3b4,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const personSimpleBike = IconData(
    0xe734,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const personSimpleRun = IconData(
    0xe730,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const personSimpleSwim = IconData(
    0xe736,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const personSimpleTaiChi = IconData(
    0xed5c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const personSimpleWalk = IconData(
    0xe73a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const plant = IconData(
    0xebae,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const play = IconData(
    0xe3d0,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const plus = IconData(
    0xe3d4,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const plusCircle = IconData(
    0xe3d6,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const pushPin = IconData(
    0xe3e2,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const radioButton = IconData(
    0xeb08,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const ruler = IconData(
    0xe6b8,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const scales = IconData(
    0xe750,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const shareNetwork = IconData(
    0xe408,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const shieldCheck = IconData(
    0xe40c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const signOut = IconData(
    0xe42a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const sliders = IconData(
    0xe432,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const slidersHorizontal = IconData(
    0xe434,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const soccerBall = IconData(
    0xe716,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const sparkle = IconData(
    0xe6a2,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const stairs = IconData(
    0xe8ec,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const star = IconData(
    0xe46a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const stethoscope = IconData(
    0xe7ea,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const target = IconData(
    0xe47c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const thermometer = IconData(
    0xe5c6,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const timer = IconData(
    0xe492,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const trash = IconData(
    0xe4a6,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const user = IconData(
    0xe4c2,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const userPlus = IconData(
    0xe4d0,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const users = IconData(
    0xe4d6,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const warning = IconData(
    0xe4e0,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const warningCircle = IconData(
    0xe4e2,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const wind = IconData(
    0xe5d2,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const wine = IconData(
    0xe6b2,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const x = IconData(
    0xe4f6,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
}

abstract final class _Fill {
  static const aperture = IconData(
    0xe00a,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const arrowCounterClockwise = IconData(
    0xe038,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const arrowDown = IconData(
    0xe03e,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const arrowUp = IconData(
    0xe08e,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const arrowsClockwise = IconData(
    0xe094,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const arrowsOutSimple = IconData(
    0xe0a6,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const barbell = IconData(
    0xe0b6,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const barcode = IconData(
    0xe0b8,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const bed = IconData(
    0xe0cc,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const beerBottle = IconData(
    0xe7b0,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const beerStein = IconData(
    0xeb62,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const bell = IconData(
    0xe0ce,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const boat = IconData(
    0xe786,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const bookOpenText = IconData(
    0xe8f2,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const bowlFood = IconData(
    0xeaa4,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const boxingGlove = IconData(
    0xea36,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const brandy = IconData(
    0xe6b4,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const calendarBlank = IconData(
    0xe10a,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const camera = IconData(
    0xe10e,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const caretDown = IconData(
    0xe136,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const caretLeft = IconData(
    0xe138,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const caretRight = IconData(
    0xe13a,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const caretUp = IconData(
    0xe13c,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const champagne = IconData(
    0xeaca,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const chartLine = IconData(
    0xe154,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const chatCircleText = IconData(
    0xe16e,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const chatText = IconData(
    0xe17a,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const check = IconData(
    0xe182,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const checkCircle = IconData(
    0xe184,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const circle = IconData(
    0xe18a,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const clock = IconData(
    0xe19a,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const clockCounterClockwise = IconData(
    0xe1a0,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const cloudArrowDown = IconData(
    0xe1ac,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const cloudArrowUp = IconData(
    0xe1ae,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const cloudCheck = IconData(
    0xe1b0,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const cloudSlash = IconData(
    0xe1b6,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const coffee = IconData(
    0xe1c2,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const cookie = IconData(
    0xe6ca,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const cookingPot = IconData(
    0xe764,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const copySimple = IconData(
    0xe1cc,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const couch = IconData(
    0xe7f6,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const dotsThree = IconData(
    0xe1fe,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const dotsThreeCircle = IconData(
    0xe200,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const downloadSimple = IconData(
    0xe20c,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const drop = IconData(
    0xe210,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const eye = IconData(
    0xe220,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const eyeSlash = IconData(
    0xe224,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const filePdf = IconData(
    0xe702,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const flag = IconData(
    0xe244,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const footprints = IconData(
    0xea88,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const forkKnife = IconData(
    0xe262,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const gear = IconData(
    0xe270,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const heartbeat = IconData(
    0xe2ac,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const image = IconData(
    0xe2ca,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const imageBroken = IconData(
    0xe7a8,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const images = IconData(
    0xe836,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const info = IconData(
    0xe2ce,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const lightbulb = IconData(
    0xe2dc,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const magnifyingGlass = IconData(
    0xe30c,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const martini = IconData(
    0xe31c,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const microphone = IconData(
    0xe326,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const minus = IconData(
    0xe32a,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const moon = IconData(
    0xe330,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const mountains = IconData(
    0xe7ae,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const musicNotes = IconData(
    0xe340,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const palette = IconData(
    0xe6c8,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const path = IconData(
    0xe39c,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const pencilSimple = IconData(
    0xe3b4,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const personSimpleBike = IconData(
    0xe734,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const personSimpleRun = IconData(
    0xe730,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const personSimpleSwim = IconData(
    0xe736,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const personSimpleTaiChi = IconData(
    0xed5c,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const personSimpleWalk = IconData(
    0xe73a,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const plant = IconData(
    0xebae,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const play = IconData(
    0xe3d0,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const plus = IconData(
    0xe3d4,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const plusCircle = IconData(
    0xe3d6,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const pushPin = IconData(
    0xe3e2,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const radioButton = IconData(
    0xeb08,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const ruler = IconData(
    0xe6b8,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const scales = IconData(
    0xe750,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const shareNetwork = IconData(
    0xe408,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const shieldCheck = IconData(
    0xe40c,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const signOut = IconData(
    0xe42a,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const sliders = IconData(
    0xe432,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const slidersHorizontal = IconData(
    0xe434,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const soccerBall = IconData(
    0xe716,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const sparkle = IconData(
    0xe6a2,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const stairs = IconData(
    0xe8ec,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const star = IconData(
    0xe46a,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const stethoscope = IconData(
    0xe7ea,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const target = IconData(
    0xe47c,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const thermometer = IconData(
    0xe5c6,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const timer = IconData(
    0xe492,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const trash = IconData(
    0xe4a6,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const user = IconData(
    0xe4c2,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const userPlus = IconData(
    0xe4d0,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const users = IconData(
    0xe4d6,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const warning = IconData(
    0xe4e0,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const warningCircle = IconData(
    0xe4e2,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const wind = IconData(
    0xe5d2,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const wine = IconData(
    0xe6b2,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
  static const x = IconData(
    0xe4f6,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
}
