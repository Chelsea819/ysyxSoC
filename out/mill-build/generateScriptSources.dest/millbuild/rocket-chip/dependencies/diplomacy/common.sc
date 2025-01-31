package millbuild.`rocket-chip`.dependencies.diplomacy

import _root_.mill.runner.MillBuildRootModule

@scala.annotation.nowarn
object MiscInfo_common {
  implicit lazy val millBuildRootModuleInfo: _root_.mill.runner.MillBuildRootModule.Info = _root_.mill.runner.MillBuildRootModule.Info(
    Vector("/home/chelsea/ysyx-workbench/ysyxSoC/out/mill-launcher/0.11.12.jar").map(_root_.os.Path(_)),
    _root_.os.Path("/home/chelsea/ysyx-workbench/ysyxSoC/rocket-chip/dependencies/diplomacy"),
    _root_.os.Path("/home/chelsea/ysyx-workbench/ysyxSoC"),
  )
  implicit lazy val millBaseModuleInfo: _root_.mill.main.RootModule.Info = _root_.mill.main.RootModule.Info(
    millBuildRootModuleInfo.projectRoot,
    _root_.mill.define.Discover[common]
  )
}
import MiscInfo_common.{millBuildRootModuleInfo, millBaseModuleInfo}
object common extends common
class common extends _root_.mill.main.RootModule.Foreign(Some(_root_.mill.define.Segments.labels("foreign-modules", "rocket-chip", "dependencies", "diplomacy", "common"))) {

//MILL_ORIGINAL_FILE_PATH=/home/chelsea/ysyx-workbench/ysyxSoC/rocket-chip/dependencies/diplomacy/common.sc
//MILL_USER_CODE_START_MARKER
import mill._
import mill.scalalib._

trait HasChisel extends ScalaModule {
  // Define these for building chisel from source
  def chiselModule: Option[ScalaModule]
  override def moduleDeps = super.moduleDeps ++ chiselModule

  def chiselPluginJar: T[Option[PathRef]]
  override def scalacOptions = T(
    (super.scalacOptions() ++ chiselPluginJar().map(path => s"-Xplugin:${path.path}")) ++ Seq("-deprecation", "-feature")
  )
  override def scalacPluginClasspath: T[Agg[PathRef]] = T(super.scalacPluginClasspath() ++ chiselPluginJar())

  // Define these for using chisel from ivy
  def chiselIvy: Option[Dep]
  override def ivyDeps = T(super.ivyDeps() ++ chiselIvy)

  def chiselPluginIvy: Option[Dep]
  override def scalacPluginIvyDeps: T[Agg[Dep]] = T(
    super.scalacPluginIvyDeps() ++ chiselPluginIvy.map(Agg(_)).getOrElse(Agg.empty[Dep])
  )
}

trait DiplomacyModule extends HasChisel {

  def cdeModule: ScalaModule

  override def moduleDeps = super.moduleDeps ++ Some(cdeModule)

  def sourcecodeIvy: Dep

  override def ivyDeps = T(super.ivyDeps() ++ Some(sourcecodeIvy))

  override def scalacOptions = T(
    super.scalacOptions() ++ Seq("-Wunused")
  )

}

}