from json import dumps
from boto3 import client

dynamodb_client = client('dynamodb', region_name='us-east-1')

HTTP_OK = 200
HTTP_NOT_FOUND = 404
HTTP_INTERNAL_SERVER_ERROR = 500
TABLE_NAME = 'cloudresumedb'

def increment_count():
    _ = dynamodb_client.update_item(
        TableName=TABLE_NAME,
        Key={'webdata': {'S': 'viewcount'}},
        UpdateExpression='SET #counter = #counter + :incr',
        ExpressionAttributeNames={'#counter': 'counter'},
        ExpressionAttributeValues={':incr': {'N': '1'}},
        ReturnValues='UPDATED_NEW'
    )

def retrieve_data():
    try:
        response = dynamodb_client.get_item(
            TableName=TABLE_NAME,
            Key={'webdata': {'S': 'viewcount'}}
        )

        item = response.get('Item')

        if item is None:
            return {
                'statusCode': HTTP_NOT_FOUND,
                'body': dumps({'error': 'Item not found'})
            }

        view_count = item.get('counter', {}).get('N')

        return {
            'statusCode': HTTP_OK,
            'body': view_count
        }

    except Exception as e:
        return {
            'statusCode': HTTP_INTERNAL_SERVER_ERROR,
            'body': dumps({'error': str(e)})
        }


def lambda_handler(event, context):
    increment_count()
    return retrieve_data()