import { Alert, Col, Row } from 'react-bootstrap';

export const AppInstructions = () => (
  <Row>
    <Col>
      <Alert variant="success">
        <Alert.Heading>Todo List App</Alert.Heading>
        Welcome to the ClearPoint SRE technical test.
        <br />
        This is Adam Lynam's solution. It runs on Fargate instances on AWS Elastic Container Services and has Continous Deployment configured.
        <br />

      </Alert>
    </Col>
  </Row>
)