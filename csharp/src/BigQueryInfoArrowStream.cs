/*
* Copyright (c) 2025 ADBC Drivers Contributors
*
* This file has been modified from its original version, which is
* under the Apache License:
*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*    http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Apache.Arrow;
using Apache.Arrow.Ipc;
using Apache.Arrow.Types;
using Apache.Arrow.Adbc;
using Apache.Arrow.Adbc.Extensions;

namespace AdbcDrivers.BigQuery
{
    /// <summary>
    /// Stream used for metadata calls
    /// </summary>
    internal class BigQueryInfoArrowStream : IArrowArrayStream
    {
        private Schema schema;
        private RecordBatch? batch;

        public BigQueryInfoArrowStream(Schema schema, IReadOnlyList<IArrowArray> data)
        {
            this.schema = schema;
            this.batch = new RecordBatch(schema, data, data[0].Length);
        }

        public Schema Schema { get { return this.schema; } }

        public ValueTask<RecordBatch?> ReadNextRecordBatchAsync(CancellationToken cancellationToken = default)
        {
            RecordBatch? batch = this.batch;
            this.batch = null;
            return new ValueTask<RecordBatch?>(batch);
        }

        public void Dispose()
        {
            this.batch?.Dispose();
            this.batch = null;
        }
    }

    /// <summary>
    /// Streaming IArrowArrayStream that yields one RecordBatch per catalog.
    /// Each call to ReadNextRecordBatchAsync processes one catalog, allowing
    /// the previous catalog's memory to be GC'd before the next is built.
    /// </summary>
    internal class ChunkedGetObjectsStream : IArrowArrayStream
    {
        private readonly BigQueryConnection _connection;
        private readonly AdbcConnection.GetObjectsDepth _depth;
        private readonly string? _dbSchemaPattern;
        private readonly string? _tableNamePattern;
        private readonly IReadOnlyList<string>? _tableTypes;
        private readonly string? _columnNamePattern;
        private readonly List<string> _catalogIds;
        private int _nextIndex;

        public ChunkedGetObjectsStream(
            BigQueryConnection connection,
            AdbcConnection.GetObjectsDepth depth,
            List<string> catalogIds,
            string? dbSchemaPattern,
            string? tableNamePattern,
            IReadOnlyList<string>? tableTypes,
            string? columnNamePattern)
        {
            _connection = connection;
            _depth = depth;
            _catalogIds = catalogIds;
            _dbSchemaPattern = dbSchemaPattern;
            _tableNamePattern = tableNamePattern;
            _tableTypes = tableTypes;
            _columnNamePattern = columnNamePattern;
            _nextIndex = 0;
        }

        public Schema Schema => StandardSchemas.GetObjectsSchema;

        public async ValueTask<RecordBatch?> ReadNextRecordBatchAsync(CancellationToken cancellationToken = default)
        {
            if (_nextIndex >= _catalogIds.Count)
                return null;

            string catalogId = _catalogIds[_nextIndex++];

            // Build one catalog's worth of data
            StringArray.Builder catalogNameBuilder = new StringArray.Builder();
            catalogNameBuilder.Append(catalogId);

            StructArray dbSchemas;
            if (_depth == AdbcConnection.GetObjectsDepth.Catalogs)
            {
                dbSchemas = new StructArray(
                    new StructType(StandardSchemas.DbSchemaSchema),
                    0,
                    new IArrowArray[]
                    {
                        new StringArray.Builder().Build(),
                        new List<IArrowArray?>().BuildListArrayForType(new StructType(StandardSchemas.TableSchema)),
                    },
                    new ArrowBuffer.BitmapBuilder().Build());
            }
            else
            {
                dbSchemas = await _connection.GetDbSchemasAsync(
                    _depth, catalogId, _dbSchemaPattern,
                    _tableNamePattern, _tableTypes, _columnNamePattern);
            }

            List<IArrowArray?> catalogDbSchemasValues = new List<IArrowArray?> { dbSchemas };

            IArrowArray[] dataArrays = new IArrowArray[]
            {
                catalogNameBuilder.Build(),
                catalogDbSchemasValues.BuildListArrayForType(new StructType(StandardSchemas.DbSchemaSchema)),
            };

            StandardSchemas.GetObjectsSchema.Validate(dataArrays);

            return new RecordBatch(Schema, dataArrays, 1);
        }

        public void Dispose()
        {
            // Nothing to dispose — each batch is owned by the caller
        }
    }
}
