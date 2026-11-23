import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/pages/route_error_page.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/timeline/timeline_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'package:kazumi/tv/pages/tv_collect_page.dart';
import 'package:kazumi/tv/pages/tv_history_page.dart';
import 'package:kazumi/tv/pages/tv_info_page.dart';
import 'package:kazumi/tv/pages/tv_init_page.dart';
import 'package:kazumi/tv/pages/tv_logs_page.dart';
import 'package:kazumi/tv/pages/tv_onboarding_page.dart';
import 'package:kazumi/tv/pages/tv_plugins_page.dart';
import 'package:kazumi/tv/pages/tv_popular_page.dart';
import 'package:kazumi/tv/pages/tv_search_page.dart';
import 'package:kazumi/tv/pages/tv_settings_page.dart';
import 'package:kazumi/tv/pages/tv_timeline_page.dart';
import 'package:kazumi/tv/pages/tv_video_page.dart';
import 'package:kazumi/tv/shell/tv_shell_page.dart';

final _tvTabTransition = CustomTransition(
  duration: const Duration(milliseconds: 90),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(opacity: animation, child: child);
  },
);

final tvTabModule = createModule(
  path: '/tab',
  register: (c) {
    c
      ..addSingleton<PopularController>(PopularController.new)
      ..addSingleton<TimelineController>(TimelineController.new)
      ..addSingleton<SearchPageController>(SearchPageController.new)
      ..route(
        '/',
        child: (context, state) => TvShellPage(location: state.uri.path),
        transition: _tvTabTransition,
        children: (sub) {
          sub
            ..route(
              '/',
              guards: [(_) => '/tab/popular/'],
              child: (context, state) => const SizedBox.shrink(),
            )
            ..module(
              createModule(
                path: '/popular',
                register: (m) {
                  m.route(
                    '/',
                    transition: TransitionType.none,
                    child: (context, state) => TvPopularPage(
                      controller: inject<PopularController>(),
                    ),
                  );
                },
              ),
            )
            ..module(
              createModule(
                path: '/timeline',
                register: (m) {
                  m.route(
                    '/',
                    transition: TransitionType.none,
                    child: (context, state) => TvTimelinePage(
                      controller: inject<TimelineController>(),
                    ),
                  );
                },
              ),
            )
            ..module(
              createModule(
                path: '/search',
                register: (m) {
                  m.route(
                    '/',
                    transition: TransitionType.none,
                    child: (context, state) => TvSearchPage(
                      controller: inject<SearchPageController>(),
                      initialQuery: state.uri.queryParameters['query'] ?? '',
                    ),
                  );
                },
              ),
            )
            ..module(
              createModule(
                path: '/collect',
                register: (m) {
                  m.route(
                    '/',
                    transition: TransitionType.none,
                    child: (context, state) => TvCollectPage(
                      controller: inject<CollectController>(),
                    ),
                  );
                },
              ),
            )
            ..module(
              createModule(
                path: '/history',
                register: (m) {
                  m.route(
                    '/',
                    transition: TransitionType.none,
                    child: (context, state) => TvHistoryPage(
                      controller: inject<HistoryController>(),
                      playbackService: inject<HistoryPlaybackService>(),
                    ),
                  );
                },
              ),
            )
            ..module(
              createModule(
                path: '/plugins',
                register: (m) {
                  m.route(
                    '/',
                    transition: TransitionType.none,
                    child: (context, state) => TvPluginsPage(
                      controller: inject<PluginsController>(),
                    ),
                  );
                },
              ),
            )
            ..module(
              createModule(
                path: '/settings',
                register: (m) {
                  m.route(
                    '/',
                    transition: TransitionType.none,
                    child: (context, state) => TvSettingsPage(
                      danmakuShieldSync: inject<DanmakuShieldSyncService>(),
                    ),
                  );
                },
              ),
            );
        },
      );
  },
);

final tvIndexModule = createModule(
  register: (c) {
    c
      ..route(
        '/',
        transition: TransitionType.none,
        child: (context, state) => TvInitPage(
          pluginsController: inject<PluginsController>(),
          collectController: inject<CollectController>(),
          shaderAssetService: inject<ShaderAssetService>(),
          myController: inject<MyController>(),
          danmakuShieldSync: inject<DanmakuShieldSyncService>(),
        ),
      )
      ..route(
        '/onboarding',
        transition: TransitionType.none,
        child: (context, state) => TvOnboardingPage(
          pluginsController: inject<PluginsController>(),
        ),
      )
      ..module(tvTabModule)
      ..module(
        createModule(
          path: '/info',
          register: (m) {
            m.route(
              '/',
              provide: (s) => s.add<InfoController>(InfoController.new),
              child: (context, state) {
                final bangumiItem = state.arguments;
                if (bangumiItem is! BangumiItem) {
                  return const RouteErrorPage(message: '番剧详情参数无效，请返回后重试。');
                }
                return TvInfoPage(
                  inputBangumiItem: bangumiItem,
                  infoController: context.read<InfoController>(),
                  pluginsController: inject<PluginsController>(),
                  collectController: inject<CollectController>(),
                  historyController: inject<HistoryController>(),
                  historyPlaybackService: inject<HistoryPlaybackService>(),
                );
              },
            );
          },
        ),
      )
      ..module(
        createModule(
          path: '/video',
          register: (m) {
            m.route(
              '/',
              provide: (s) => s
                ..add<VideoPageController>(VideoPageController.new)
                ..add<PlayerController>(PlayerController.new),
              child: (context, state) {
                final args = state.arguments;
                if (args is! VideoPlaybackArgs) {
                  return const RouteErrorPage(message: '播放参数无效，请返回后重试。');
                }
                return TvVideoPage(
                  args: args,
                  playerController: context.read<PlayerController>(),
                  videoPageController: context.read<VideoPageController>(),
                  historyController: inject<HistoryController>(),
                  myController: inject<MyController>(),
                );
              },
            );
          },
        ),
      )
      ..route(
        '/logs',
        child: (context, state) => const TvLogsPage(),
      );
  },
);
