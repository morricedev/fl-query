import 'package:fl_query/src/core/core.dart';
import 'package:fl_query/src/core/query_cache.dart';
import 'package:fl_query/src/core/retryer.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

import '../../helpers/utils.dart';

void main() {
  group('QueryCache', () {
    late QueryClient queryClient;
    late QueryCache queryCache;

    setUp(() {
      queryClient = new QueryClient();
      queryCache = queryClient.getQueryCache();
    });

    tearDown(() {
      queryClient.clear();
    });
    group('subscribe', () {
      test('Should pass the correct query', () async {
        final QueryKey key = queryKey();
        var _event;
        subscriber(event) {
          _event ??= event;
        }

        final unsubscribe = queryCache.subscribe(subscriber);
        final Map<String, dynamic> data = {'foo': "foo"};
        queryClient.setQueryData(key, (_) => data);
        final query = queryCache.find(key);
        await Future.delayed(Duration(milliseconds: 1));
        expect(_event, isA<QueryCacheNotifyEvent>());
        expect(
          (_event as QueryCacheNotifyEvent).type,
          QueryCacheNotifyEventType.queryAdded,
        );
        expect(
          (_event as QueryCacheNotifyEvent).query,
          same(query),
        );
        unsubscribe();
      });

      test('Should notify listeners When new query is added', () async {
        final key = queryKey();
        late bool called;
        callback(_) {
          called = true;
        }

        queryCache.subscribe(callback);
        queryClient.prefetchQuery(
          queryKey: key,
          queryFn: (_) async => {'data': "data"},
        );
        await Future.delayed(Duration(milliseconds: 100));

        expect(called, isTrue);
      });

      test('Should include the queryCache and query When notifying listeners',
          () async {
        final key = queryKey();
        QueryCacheNotifyEvent? _event;
        callback(event) => _event ??= event;
        queryCache.subscribe(callback);
        queryClient.prefetchQuery(
          queryKey: key,
          queryFn: (_) => {'data': "data"},
        );
        final query = queryCache.find(key);
        await Future.delayed(Duration(milliseconds: 100));
        expect(_event, isA<QueryCacheNotifyEvent>());
        expect(_event?.type, QueryCacheNotifyEventType.queryAdded);
        expect(_event?.query, same(query));
      });

      test('Should notify subscribers When new query with initialData is added',
          () async {
        final key = queryKey();
        late bool called;
        callback(_) => called = true;
        queryCache.subscribe(callback);
        queryClient
            .prefetchQuery<Map<String, dynamic>, dynamic, Map<String, dynamic>>(
          queryKey: key,
          queryFn: (_) => {'data': "Data"},
          options: FetchQueryOptions(initialData: {"data": "initial-data"}),
        );
        await Future.delayed(Duration(milliseconds: 100));
        expect(called, isTrue);
      });
    });

    group('find', () {
      test('Should filter correctly', () async {
        final key = queryKey();
        await queryClient.prefetchQuery(
          queryKey: key,
          queryFn: (_) => {"data": 'data1'},
        );
        final query = queryCache.find(key);
        expect(query, isNotNull);
      });

      test(
        'Should filter correctly When called with exact set to false',
        () async {
          final key = queryKey();
          await queryClient.prefetchQuery(
            queryKey: key,
            queryFn: (_) => {"data": 'data1'},
          );
          final query = queryCache.find(key, QueryFilters(exact: false));
          expect(query, isNotNull);
        },
      );
    });

    group('findAll', () {
      test('Should filter correctly', () async {
        final key1 = queryKey();
        final key2 = queryKey();
        final key3 = QueryKey.fromList(['posts', "1"]);
        await queryClient.prefetchQuery(
          queryKey: key1,
          queryFn: (_) => {"data": 'data1'},
        );
        await queryClient.prefetchQuery(
          queryKey: key2,
          queryFn: (_) => {"data": 'data2'},
        );
        await queryClient.prefetchQuery(
          queryKey: key3,
          queryFn: (_) => {"data": 'data4'},
        );
        await queryClient.invalidateQueries(queryKeys: key2);
        final query1 = queryCache.find(key1);
        final query2 = queryCache.find(key2);
        final query4 = queryCache.find(key3);

        expect(queryCache.findAll(key1), equals([query1]));
        expect(queryCache.findAll(), equals([query1, query2, query4]));
        expect(
          queryCache.findAll(key1, QueryFilters(active: false)),
          equals([query1]),
        );
        expect(
            queryCache.findAll(key1, QueryFilters(active: true)), equals([]));
        expect(queryCache.findAll(key1, QueryFilters(stale: true)), equals([]));
        expect(
          queryCache.findAll(key1, QueryFilters(stale: false)),
          equals([query1]),
        );
        expect(
          queryCache.findAll(key1, QueryFilters(stale: false, active: true)),
          equals([]),
        );
        expect(
          queryCache.findAll(key1, QueryFilters(active: false, stale: false)),
          equals([query1]),
        );
        expect(
          queryCache.findAll(
            key1,
            QueryFilters(active: false, stale: false, exact: true),
          ),
          equals([query1]),
        );

        expect(queryCache.findAll(key2), equals([query2]));
        expect(
          queryCache.findAll(key2, QueryFilters(stale: null)),
          equals([query2]),
        );
        expect(
          queryCache.findAll(key2, QueryFilters(stale: true)),
          equals([query2]),
        );
        expect(
          queryCache.findAll(key2, QueryFilters(stale: false)),
          equals([]),
        );

        expect(
          queryCache.findAll(
            null,
            QueryFilters(predicate: (query) => query == query4),
          ),
          equals([query4]),
        );
        expect(queryCache.findAll(QueryKey('posts')), equals([query4]));
      });

      test('Should return all the queries When no filters are defined',
          () async {
        final key1 = queryKey();
        final key2 = queryKey();
        await queryClient.prefetchQuery(
          queryKey: key1,
          queryFn: (_) => {"data": 'data1'},
        );
        await queryClient.prefetchQuery(
          queryKey: key2,
          queryFn: (_) {
            return {"data": 'data2'};
          },
        );
        expect(queryCache.findAll().length, 2);
      });
    });

    group('QueryCacheConfig.onError', () {
      test('should be called when a query errors', () async {
        final key = queryKey();
        var errorArg;
        var queryArg;
        onError(error, query) {
          errorArg = error;
          queryArg = query;
        }

        final testCache = new QueryCache(onError: onError);
        final testClient = new QueryClient(queryCache: testCache);
        await testClient
            .prefetchQuery<Map<String, dynamic>, dynamic, Map<String, dynamic>>(
                queryKey: key, queryFn: (_) => Future.error('error'));
        final query = testCache.find(key);
        expect(errorArg, equals("error"));
        expect(queryArg, equals(query));
      });
    });

    group('QueryCacheConfig.onSuccess', () {
      test('should be called when a query is successful', () async {
        final key = queryKey();
        var dataArg;
        var queryArg;
        onData(data, query) {
          dataArg = data;
          queryArg = query;
        }

        final testCache = new QueryCache(onData: onData);
        final testClient = new QueryClient(queryCache: testCache);
        await testClient
            .prefetchQuery<Map<String, dynamic>, dynamic, Map<String, dynamic>>(
          queryKey: key,
          queryFn: (_) => Future.value({"data": 5}),
        );
        final query = testCache.find(key);
        expect(dataArg, equals({"data": 5}));
        expect(queryArg, equals(query));
      });
    });
    group('QueryCache.add', () {
      test('should not try to add a query already added to the cache',
          () async {
        final key = queryKey();
        final hash = key.key;

        await queryClient.prefetchQuery(
            queryKey: key, queryFn: (_) => {"data": 'data1'});

        // Directly add the query from the cache
        // to simulate a race condition
        final query = queryCache.queriesMap[hash] as Query;

        // No error should be thrown when trying to add the query
        queryCache.add(query);
        expect(queryCache.queries.length, 1);

        // Clean-up to avoid an error when queryClient.clear()
        queryCache.remove(query);
      });
    });

    group('QueryCache.remove', () {
      test('should not try to remove a query already removed from the cache',
          () async {
        final key = queryKey();
        final hash = key.key;

        await queryClient.prefetchQuery(
            queryKey: key, queryFn: (_) => {"data": 'data1'});

        // Directly remove the query from the cache
        // to simulate a race condition
        final query = queryCache.queriesMap[hash] as Query;
        queryCache.queriesMap.remove(hash);

        // No error should be thrown when trying to remove the query
        expect(() => queryCache.remove(query), isNot(throwsException));
      });
    });
  });
}
